# Step 1: Prerequisites Setup

## 1.1 AWS Account Setup
  - Create an https://aws.amazon.com/free/ if you don't have one
  - Note your AWS Account ID

## 1.2 Install Required Tools

### Install AWS CLI v2
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### Install Terraform
```bash
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

### Install Java 8 and Maven
```bash
sudo apt update
sudo apt install openjdk-8-jdk maven -y
```

## 1.3 Verify installations
```bash
aws --version
terraform --version
java -version
mvn --version
```

# Step 2: Configure AWS Credentials

## 2.1 Create IAM User
  - Go to AWS Console → IAM → Users → Create User
  - Attach policies: AdministratorAccess (for simplicity, use more restrictive policies in production)
  - Generate Access Key and Secret Key

## 2.2 Configure AWS CLI
```bash
aws configure
```
Enter:
- AWS Access Key ID: [your-access-key]
- AWS Secret Access Key: [your-secret-key]
- Default region name: us-east-1
- Default output format: json

## 2.3 Create EC2 Key Pair
```bash
aws ec2 create-key-pair --key-name java-app-keypair --query 'KeyMaterial' --output text > ~/.ssh/java-app-keypair.pem
chmod 400 ~/.ssh/java-app-keypair.pem
```

# Step 3: Prepare Terraform Infrastructure

## 3.1 Navigate to infrastructure directory
``` bash
cd DevOps-Project-01/infrastructure
```

## 3.2 Create terraform.tfvars file
```bash
cat > terraform.tfvars << EOF
environment         = "dev"
aws_region         = "us-east-1"
vpc_cidr           = "192.168.0.0/16"
public_subnets     = ["192.168.1.0/24", "192.168.2.0/24"]
private_subnets    = ["192.168.3.0/24", "192.168.4.0/24"]
availability_zones = ["us-east-1a", "us-east-1b"]
db_name           = "javaapp"
db_username       = "admin"
db_password       = "SecurePassword123!"
key_name          = "java-app-keypair"
instance_type     = "t3.micro"
asg_min_size      = 2
asg_max_size      = 4
asg_desired_capacity = 2
EOF
```

## 3.3 Create S3 bucket for Terraform state (optional but recommended)
```bash  
aws s3 mb s3://devops-project-01-bucket
```
# Step 4: Deploy AWS Infrastructure with Terraform

## 4.1 Initialize Terraform
```bash
cd DevOps-Project-01/infrastructure
terraform init
```

## 4.2 Validate the configuration
```bash
terraform validate
```

## 4.3 Plan the infrastructure deployment
```bash
terraform plan -out=tfplan
```
Review the plan to ensure all resources are correct.

## 4.4 Apply the infrastructure
```bash
terraform apply tfplan
```
This will create:
- VPC with public/private subnets across 2 AZs
- Security groups for web, app, and database tiers
- Application Load Balancer with health checks
- Auto Scaling Group with launch template
- RDS MySQL database with automated backups
- CloudWatch monitoring and alerting

## 4.5 Verify deployment and save outputs
```bash
# Check all outputs
terraform output

# Save important values for later use
export ALB_DNS=$(terraform output -raw alb_dns_name)
export RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
export APP_URL=$(terraform output -raw application_url)

echo "Application will be available at: $APP_URL"
echo "Database endpoint: $RDS_ENDPOINT"
```

Note: The infrastructure deployment will take 5-10 minutes to complete. The RDS instance creation takes the longest time.

# Step 5: Build Java Application

## 5.1 Navigate to Java application directory
```bash
cd ../Java-Login-App
```

## 5.2 Update database configuration
Edit src/main/resources/application.properties:
```bash
# Use the RDS endpoint from Terraform output
cat > src/main/resources/application.properties << EOF
spring.datasource.url=jdbc:mysql://${RDS_ENDPOINT}:3306/javaapp
spring.datasource.username=admin
spring.datasource.password=SecurePassword123!
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver
spring.jpa.database-platform=org.hibernate.dialect.MySQL8Dialect
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=false
server.port=8080
logging.level.org.springframework.web=INFO
logging.level.org.hibernate=INFO
spring.mvc.view.prefix=/pages/
spring.mvc.view.suffix=.jsp
EOF
```

## 5.3 Build the application
```bash
mvn clean package -DskipTests
```

## 5.4 Verify WAR file is created
```bash
ls -la target/*.war
```
# Step 6: Deploy Application to EC2 Instances

## 6.1 Upload WAR file to S3
```bash
aws s3 cp target/dptweb-1.0.war s3://devops-project-01-bucket/dptweb-1.0.war
```
(If the bucket does not exist yet, create it first with `aws s3 mb s3://devops-project-01-bucket`.)

## 6.2 Get EC2 instance IDs from Auto Scaling Group
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "dev-asg" \
  --region us-east-1 \
  --query 'AutoScalingGroups[0].Instances[].InstanceId' \
  --output text
```

## 6.3 Create and run deployment script
```bash
cat > deploy.sh << 'EOF'
#!/bin/bash
set -euo pipefail

echo "Getting instances from Auto Scaling Group..."
INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "dev-asg" \
  --region us-east-1 \
  --query 'AutoScalingGroups[0].Instances[].InstanceId' \
  --output text)

if [[ -z "${INSTANCE_IDS:-}" ]]; then
  echo "No instances found in Auto Scaling Group 'dev-asg'"
  exit 1
fi

echo "Found instances: ${INSTANCE_IDS}"

for INSTANCE_ID in ${INSTANCE_IDS}; do
  echo "Deploying to instance: ${INSTANCE_ID}"
  aws ssm send-command \
    --instance-ids "${INSTANCE_ID}" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo aws s3 cp s3://devops-project-01-bucket/dptweb-1.0.war /opt/tomcat/webapps/","sudo systemctl restart tomcat","sudo systemctl status tomcat"]' \
    --region us-east-1 \
    --output text
  echo "Deployment command sent to instance ${INSTANCE_ID}"
done

echo "Deployment script completed. Check SSM command history for results."
EOF

chmod +x deploy.sh
./deploy.sh
```
# Step 7: Configure Database

## 7.1 Get RDS endpoint from Terraform outputs
```bash
cd ../infrastructure
export RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
export RDS_PORT=$(terraform output -raw rds_port)

# Extract hostname without port (in case endpoint includes port)
export RDS_HOST=$(echo $RDS_ENDPOINT | cut -d':' -f1)

echo "RDS Host: $RDS_HOST"
echo "RDS Port: $RDS_PORT"
```

## 7.2 Connect to RDS and initialize database
```bash
# Connect to RDS using separate host and port
mysql -h $RDS_HOST -P $RDS_PORT -u admin -p
# Enter password: SecurePassword123!

# Alternative: if the above doesn't work, try without specifying port
# mysql -h $RDS_HOST -u admin -p
```

## 7.3 Create database schema
  CREATE DATABASE IF NOT EXISTS javaapp;
  USE javaapp;

  CREATE TABLE IF NOT EXISTS Employee (
      id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      first_name VARCHAR(250),
      last_name VARCHAR(250),
      email VARCHAR(250) UNIQUE,
      username VARCHAR(250) UNIQUE,
      password VARCHAR(250),
      regdate TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );

  -- Insert sample data for testing
  INSERT INTO Employee (first_name, last_name, email, username, password) VALUES
  ('Admin', 'User', 'admin@example.com', 'admin', 'admin123'),
  ('Sample', 'User', 'user1@example.com', 'user1', 'password123');

# Step 8: Verify Deployment and Test Application

## 8.1 Get Application Load Balancer DNS name and test endpoints
```bash
cd ../infrastructure  # adjust path if already inside this directory
export ALB_DNS=$(terraform output -raw alb_dns_name)
export APP_URL=$(terraform output -raw application_url)
echo "ALB DNS: $ALB_DNS"
echo "Application URL: $APP_URL"
```

## 8.2 Test application health
```bash
# Test ALB health endpoint (static health page)
curl -I http://$ALB_DNS/

# Test application endpoint (allow ~60s after deployment)
curl -I $APP_URL
```
Both commands should return `HTTP/1.1 200` once Tomcat finishes restarting on every instance.

## 8.3 Test application in browser
Open your browser and navigate to:
```
$APP_URL
```
Or directly use: http://$ALB_DNS/dptweb-1.0/

## 8.4 Test login functionality
  - Use the sample accounts created in Step 7.3:
    - Username: admin / Password: admin123
    - Username: user1 / Password: password123
  - (Optional) Register a new user and verify the record is added to the `Employee` table.

## 8.5 Monitor application logs and health
### Check CloudWatch logs
  aws logs describe-log-groups --log-group-name-prefix "/aws/tomcat" --region us-east-1
  aws logs tail /aws/tomcat/dev --region us-east-1 --follow

### Check EC2 instance health
  aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn) --region us-east-1

# Additional Important Notes:

  Security Best Practices Implemented:

  - EC2 instances deployed in private subnets
  - RDS database isolated in private subnets
  - Security groups with minimal required access
  - Application Load Balancer handling public traffic

  Monitoring and Maintenance:

  - CloudWatch monitoring automatically configured
  - Auto Scaling ensures high availability
  - RDS automated backups enabled
  - Health checks monitor application state

## Troubleshooting Commands:

### Check infrastructure status
  terraform output

### View EC2 instances
  aws ec2 describe-instances --filters "Name=tag:Environment,Values=dev"

### Check load balancer targets
  aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)

### Monitor application logs
  aws logs tail /aws/tomcat/application --follow

# 🚨 IMPORTANT: Clean Up Resources to Avoid AWS Charges

**This is a practice project - you MUST clean up all resources after completion to avoid ongoing AWS charges!**

## Option 1: Complete Infrastructure Cleanup with Terraform (Recommended)

### Step 1: Destroy all Terraform-managed resources
```bash
cd infrastructure

# Review what will be destroyed
terraform plan -destroy

# Destroy all resources (this will take 5-10 minutes)
terraform destroy -auto-approve

# Verify all resources are destroyed
terraform show
```

### Step 2: Clean up S3 buckets and manual resources
```bash
# Remove S3 bucket contents and bucket
aws s3 rm s3://devops-project-01-bucket --recursive
aws s3 rb s3://devops-project-01-bucket

# Remove EC2 key pair
aws ec2 delete-key-pair --key-name java-app-keypair
rm ~/.ssh/java-app-keypair.pem
```

## Option 2: Manual Cleanup (if Terraform fails)

If `terraform destroy` fails, manually delete resources in this order:

### 1. Stop Auto Scaling Group
```bash
# Scale down ASG to 0 instances
aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name dev-asg \
    --min-size 0 \
    --max-size 0 \
    --desired-capacity 0

# Wait for instances to terminate, then delete ASG
aws autoscaling delete-auto-scaling-group \
    --auto-scaling-group-name dev-asg \
    --force-delete
```

### 2. Delete Load Balancer
```bash
# Get ALB ARN
ALB_ARN=$(aws elbv2 describe-load-balancers --names dev-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Delete ALB
aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN

# Delete target group
TG_ARN=$(aws elbv2 describe-target-groups --names dev-app-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
aws elbv2 delete-target-group --target-group-arn $TG_ARN
```

### 3. Delete RDS Database
```bash
# Delete RDS instance (skip final snapshot for practice)
aws rds delete-db-instance \
    --db-instance-identifier dev-mysql \
    --skip-final-snapshot \
    --delete-automated-backups
```

### 4. Delete VPC Resources
```bash
# This will be done by terraform destroy, but if needed manually:
# Delete NAT Gateway, Internet Gateway, Subnets, and VPC
# (Complex process - prefer terraform destroy)
```

## Option 3: AWS Console Cleanup

If CLI commands fail, use AWS Management Console:

1. **EC2 Dashboard**:
   - Terminate all instances
   - Delete Auto Scaling Groups
   - Delete Launch Templates
   - Delete Load Balancers
   - Delete Target Groups

2. **RDS Dashboard**:
   - Delete database instances
   - Delete subnet groups
   - Delete parameter groups

3. **VPC Dashboard**:
   - Delete NAT Gateways
   - Release Elastic IPs
   - Delete Subnets
   - Delete Route Tables
   - Delete Internet Gateways
   - Delete Security Groups
   - Delete VPC

4. **CloudWatch**:
   - Delete log groups
   - Delete dashboards
   - Delete alarms

5. **SNS**:
   - Delete topics and subscriptions

## Cost-Saving Tips for Practice

### Use Free Tier Resources
```bash
# In terraform.tfvars, use free tier eligible resources:
instance_type = "t2.micro"        # Free tier eligible
db_instance_class = "db.t3.micro" # Free tier eligible for RDS
```

### Set Up Billing Alerts
```bash
# Create billing alarm to monitor costs
aws cloudwatch put-metric-alarm \
    --alarm-name "Billing-Alert" \
    --alarm-description "Billing alarm" \
    --metric-name EstimatedCharges \
    --namespace AWS/Billing \
    --statistic Maximum \
    --period 86400 \
    --threshold 10 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=Currency,Value=USD
```

### Practice Schedule
- **Deploy**: During active practice time
- **Destroy**: Immediately after practice session
- **Max Runtime**: Keep infrastructure running for max 2-4 hours

## Verification Commands

After cleanup, verify no resources remain:

```bash
# Check EC2 instances
aws ec2 describe-instances --query 'Reservations[*].Instances[?State.Name!=`terminated`]'

# Check RDS instances
aws rds describe-db-instances

# Check Load Balancers
aws elbv2 describe-load-balancers

# Check VPCs (should only show default VPC)
aws ec2 describe-vpcs

# Check S3 buckets
aws s3 ls

# Get current month billing (if configured)
aws ce get-dimension-values \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --dimension SERVICE
```

**⚠️ Remember: AWS charges for running resources even if you're not using them actively. Always clean up after practice!**

Your Java web application is now deployed on AWS following the 3-tier architecture with high availability, auto-scaling, and proper security configurations!




# Infrastructure Status Update

All required Terraform modules have been successfully created and are ready for deployment:

## Modules Structure ✅
```
infrastructure/modules/
├── vpc/
│   ├── main.tf      # VPC, subnets, gateways
│   ├── variables.tf
│   └── outputs.tf
├── security/
│   ├── main.tf      # Security groups
│   ├── variables.tf
│   └── outputs.tf
├── alb/
│   ├── main.tf      # Application Load Balancer, target groups
│   ├── variables.tf
│   └── outputs.tf
├── asg/
│   ├── main.tf      # Auto Scaling Group, launch template
│   ├── variables.tf
│   ├── outputs.tf
│   └── userdata.sh  # EC2 instance configuration script
├── rds/
│   ├── main.tf      # RDS MySQL instance, subnet group
│   ├── variables.tf
│   └── outputs.tf
└── monitoring/
    ├── main.tf      # CloudWatch alarms, dashboards
    ├── variables.tf
    └── outputs.tf
```

## Ready to Deploy! 🚀

The infrastructure is now complete with:
- ✅ **3-Tier Architecture**: Presentation, Application, and Data tiers
- ✅ **High Availability**: Multi-AZ deployment across us-east-1a and us-east-1b
- ✅ **Auto Scaling**: Dynamic scaling based on CPU metrics
- ✅ **Security**: Security groups with least privilege access
- ✅ **Monitoring**: CloudWatch dashboards and alerting
- ✅ **Database**: RDS MySQL with automated backups

## Next Steps for Deployment

Continue with Step 4 (Deploy Infrastructure) as all modules are now ready.