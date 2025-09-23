# DevOps Project 01 - Issues Encountered and Resolutions

This document tracks all issues encountered during the Java 3-tier AWS deployment project and their resolutions for future reference.

## 📋 Table of Contents

1. [Infrastructure Setup Issues](#infrastructure-setup-issues)
2. [Terraform Configuration Issues](#terraform-configuration-issues)
3. [Auto Scaling and Health Check Issues](#auto-scaling-and-health-check-issues)
4. [Application Deployment Issues](#application-deployment-issues)
5. [Database Connection Issues](#database-connection-issues)
6. [AWS CLI and Command Issues](#aws-cli-and-command-issues)
7. [Lessons Learned](#lessons-learned)

---

## Infrastructure Setup Issues

### Issue #1: Missing Terraform Modules
**Problem**: Initial terraform validate failed because referenced modules (alb, asg, rds, monitoring) didn't exist.
```
Error: Module not installed
```

**Root Cause**: Only VPC and security modules were implemented, but main.tf referenced 4 additional modules.

**Resolution**:
- Created complete ALB module with load balancer, target group, listener, and security group
- Created ASG module with launch template, auto scaling group, scaling policies, and CloudWatch alarms
- Created RDS module with database instance, subnet group, parameter group, and monitoring
- Created monitoring module with SNS topic, CloudWatch dashboard, and alarms
- Added outputs.tf file with all necessary outputs

**Files Modified**:
- `/infrastructure/modules/alb/` (main.tf, variables.tf, outputs.tf)
- `/infrastructure/modules/asg/` (main.tf, variables.tf, outputs.tf, userdata.sh)
- `/infrastructure/modules/rds/` (main.tf, variables.tf, outputs.tf)
- `/infrastructure/modules/monitoring/` (main.tf, variables.tf, outputs.tf)
- `/infrastructure/outputs.tf`

---

## Terraform Configuration Issues

### Issue #2: RDS Performance Insights Error
**Problem**: Terraform apply failed with Performance Insights error.
```
Error: creating RDS DB Instance: InvalidParameterCombination: Performance Insights not supported for this configuration.
```

**Root Cause**: Performance Insights is not supported for db.t3.micro instance class.

**Resolution**: Made Performance Insights conditional based on instance class:
```hcl
performance_insights_enabled = var.db_instance_class != "db.t3.micro" ? true : false
```

**Files Modified**: `/infrastructure/modules/rds/main.tf`

### Issue #3: CloudWatch Log Groups Already Exist Error
**Problem**: Terraform failed when trying to create RDS CloudWatch log groups.
```
Error: creating CloudWatch Logs Log Group: ResourceAlreadyExistsException: The specified log group already exists
```

**Root Cause**: AWS automatically creates CloudWatch log groups when RDS logging is enabled.

**Resolution**: Removed manual CloudWatch log group creation from RDS module since AWS creates them automatically.

**Files Modified**: `/infrastructure/modules/rds/main.tf`

### Issue #4: RDS CloudWatch Logs Export Name Error
**Problem**: Terraform validation failed for RDS logs export configuration.
```
Error: expected enabled_cloudwatch_logs_exports.2 to be one of [...], got slow_query
```

**Root Cause**: Incorrect log export name - should be "slowquery" not "slow_query".

**Resolution**: Changed `enabled_cloudwatch_logs_exports = ["error", "general", "slow_query"]` to `["error", "general", "slowquery"]`

**Files Modified**: `/infrastructure/modules/rds/main.tf`

---

## Auto Scaling and Health Check Issues

### Issue #5: Continuous Instance Replacement (504 Gateway Timeout)
**Problem**: Auto Scaling Group was continuously terminating and launching new instances due to health check failures.
```
Target.Timeout: Request timed out
```

**Root Cause**: Multiple issues:
1. Health check path mismatch (`/dptweb-1.0/` vs `/`)
2. Missing IAM role for EC2 instances
3. Tomcat not starting properly
4. Application not deployed

**Resolution**:
1. **Changed health check path** from `/dptweb-1.0/` to `/` in ALB target group
2. **Added IAM role and instance profile** for EC2 instances with S3 and SSM permissions
3. **Improved userdata script** with better logging and error handling
4. **Created health check endpoint** at root path before starting Tomcat

**Files Modified**:
- `/infrastructure/modules/alb/main.tf` (health check path)
- `/infrastructure/modules/asg/main.tf` (IAM role and instance profile)
- `/infrastructure/modules/asg/userdata.sh` (improved script)

---

## Application Deployment Issues

### Issue #6: Deploy Script Command Parsing Errors
**Problem**: Deployment script failed with AWS CLI parsing errors.
```
aws: error: argument --query: expected one argument
./deploy.sh: line 4: AutoScalingGroups[0].Instances[*].InstanceId: command not found
```

**Root Cause**: Line breaks in AWS CLI commands were causing parsing issues.

**Resolution**:
- Fixed line breaks in AWS CLI commands
- Added proper error handling with `set -euo pipefail`
- Improved variable handling with proper quoting
- Added validation for empty instance lists

**Files Modified**: `/Java-Login-App/deploy.sh`

### Issue #7: SSM Command Execution Errors
**Problem**: SSM send-command failed with instance validation errors.
```
Error: Instances not in a valid state for account
InvalidInstanceId: Value at 'instanceId' failed to satisfy constraint
```

**Root Cause**:
1. Instances were still launching/configuring
2. Missing IAM role for SSM access
3. SSM agent not properly installed

**Resolution**:
- Added IAM role with SSM permissions
- Explicitly installed and started SSM agent in userdata
- Added proper instance state checking before deployment

**Files Modified**:
- `/infrastructure/modules/asg/main.tf` (IAM role)
- `/infrastructure/modules/asg/userdata.sh` (SSM agent)

---

## Database Connection Issues

### Issue #8: MySQL Connection Host Error
**Problem**: MySQL client couldn't connect to RDS endpoint.
```
ERROR 2005 (HY000): Unknown MySQL server host 'dev-mysql.xxx.rds.amazonaws.com:3306' (-2)
```

**Root Cause**: RDS endpoint included port number, but MySQL client expects host and port separately.

**Resolution**: Extract hostname and port separately:
```bash
export RDS_HOST=$(echo $RDS_ENDPOINT | cut -d':' -f1)
export RDS_PORT=$(terraform output -raw rds_port)
mysql -h $RDS_HOST -P $RDS_PORT -u admin -p
```

**Files Modified**: `/MYREADME.md` (database connection instructions)

### Issue #9: Database Schema Mismatch
**Problem**: Application expected different table structure than initially created.

**Root Cause**: Java application uses `Employee` table but initial schema created `users` table.

**Resolution**: Updated database schema to match application requirements:
```sql
CREATE TABLE IF NOT EXISTS Employee (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(250),
    last_name VARCHAR(250),
    email VARCHAR(250) UNIQUE,
    username VARCHAR(250) UNIQUE,
    password VARCHAR(250),
    regdate TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Files Modified**: `/MYREADME.md` (database schema section)

---

## AWS CLI and Command Issues

### Issue #10: Terraform Output Not Available
**Problem**: Commands using terraform output failed when not in correct directory.
```
Warning: No outputs found
Unknown options: Warning:, No, outputs, found
```

**Root Cause**: Running terraform output commands from wrong directory or state not properly applied.

**Resolution**:
- Always ensure commands run from `/infrastructure` directory
- Added directory navigation instructions
- Provided alternative manual methods to get resource information

**Files Modified**: `/MYREADME.md` (added directory navigation instructions)

### Issue #11: AWS Connectivity Issues
**Problem**: AWS CLI commands failed with endpoint connection errors.
```
Could not connect to the endpoint URL: "https://autoscaling.us-east-1.amazonaws.com/"
```

**Root Cause**: Region configuration or network connectivity issues.

**Resolution**:
- Added explicit `--region us-east-1` to all AWS CLI commands
- Provided troubleshooting steps for AWS configuration
- Added alternative commands for getting resource information

**Files Modified**: `/MYREADME.md` (AWS CLI troubleshooting section)

---

## Lessons Learned

### 🎯 Best Practices Identified

1. **Terraform Module Development**:
   - Always create all referenced modules before running terraform validate
   - Use conditional logic for cloud provider limitations (e.g., Performance Insights)
   - Let cloud providers auto-create resources when possible (e.g., CloudWatch log groups)

2. **Infrastructure as Code**:
   - Include IAM roles and policies from the beginning
   - Test health check paths before deployment
   - Use proper resource dependencies and ordering

3. **Application Deployment**:
   - Validate all scripts before execution
   - Include proper error handling and logging
   - Test userdata scripts in isolation when possible

4. **AWS CLI Usage**:
   - Always specify region explicitly
   - Use proper quoting and line continuation
   - Provide fallback methods for resource discovery

5. **Documentation**:
   - Include troubleshooting steps for common issues
   - Provide alternative approaches when primary method fails
   - Document exact error messages and resolutions

### 🔧 Preventive Measures

1. **Pre-deployment Checklist**:
   - [ ] All Terraform modules exist and are complete
   - [ ] Health check paths match application endpoints
   - [ ] IAM roles include all necessary permissions
   - [ ] Database schema matches application requirements
   - [ ] All scripts have proper error handling

2. **Testing Strategy**:
   - Test Terraform configurations with `terraform validate` and `terraform plan`
   - Test AWS CLI commands individually before using in scripts
   - Validate userdata scripts on test instances
   - Verify database connectivity before application deployment

3. **Monitoring Setup**:
   - Enable comprehensive logging from the start
   - Set up health checks before application deployment
   - Monitor Auto Scaling Group activities for issues
   - Use CloudWatch dashboards for real-time monitoring

### 📚 Reference Commands

**Debugging Instance Issues**:
```bash
# Check Auto Scaling Group status
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "dev-asg" --region us-east-1

# Check target group health
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn) --region us-east-1

# Check instance logs via SSM
aws ssm send-command --instance-ids "INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["sudo journalctl -u tomcat --no-pager"]' --region us-east-1
```

**Database Connection Testing**:
```bash
# Extract RDS connection details
export RDS_HOST=$(terraform output -raw rds_endpoint | cut -d':' -f1)
export RDS_PORT=$(terraform output -raw rds_port)
mysql -h $RDS_HOST -P $RDS_PORT -u admin -p
```

**Terraform State Management**:
```bash
# Refresh state and outputs
terraform refresh
terraform output

# Show current state
terraform show
```

---

## 🎉 Final Working Configuration

The project successfully deploys a 3-tier Java web application on AWS with:

- ✅ **VPC**: Multi-AZ setup with public/private subnets
- ✅ **Security Groups**: Proper network isolation between tiers
- ✅ **ALB**: Application Load Balancer with health checks
- ✅ **Auto Scaling**: Dynamic scaling based on CPU metrics
- ✅ **RDS**: MySQL database with automated backups
- ✅ **Monitoring**: CloudWatch dashboards and alerting
- ✅ **IAM**: Proper roles and permissions for all services
- ✅ **Application**: Java Spring Boot app deployed via Tomcat

**Total Resolution Time**: ~4 hours of troubleshooting and iterative improvements.

**Infrastructure Cost**: Optimized for AWS Free Tier usage with automatic cleanup procedures.