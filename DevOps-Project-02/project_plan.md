# Project Plan: Scalable VPC Architecture on AWS

## 1. High-Level Overview
**Goal**: Deploy a secure, scalable, and modular virtual network architecture on AWS.
**Architecture**:
- **Two VPCs**:
  - `VPC-A` (Bastion): Public entry point.
  - `VPC-B` (Application): Private application servers.
- **Connectivity**: Transit Gateway for VPC peering; NAT Gateway for outbound internet; Internet Gateway for inbound/outbound.
- **Compute**: Auto Scaling Group (ASG) for high availability.
- **Load Balancing**: Network Load Balancer (NLB) for traffic distribution.
- **Observability**: CloudWatch Logs for VPC Flow Logs and Application metrics.

## 1.1 Detailed Architecture & Traffic Flows

This section describes how the various AWS services interact to enable connectivity, security, and scalability.

### 1. Public Web Access (User -> Web App)
*Services involved: IGW, Route Tables, NLB, Target Group, Security Groups, EC2.*
1.  **User Request**: User enters the NLB DNS name.
2.  **Internet Gateway (IGW)**: Traffic enters `VPC-App`.
3.  **Route Table (Public)**: Routes traffic to the Public Subnets.
4.  **Network Load Balancer (NLB)**: Receives traffic on Port 80.
5.  **Target Group**: Forwards traffic to registered targets.
6.  **Security Group (App SG)**: **Inbound Rule** allows traffic from `0.0.0.0/0` on Port 80.
7.  **EC2 Instance**: Apache Web Server processes the request.

### 2. Outbound Internet Access (Private Instances)
*Services involved: Route Tables, NAT Gateway, IGW.*
1.  **EC2 Instance**: Initiates request (e.g., `yum update`).
2.  **Route Table (Private)**: Route `0.0.0.0/0` points to the **NAT Gateway**.
3.  **NAT Gateway**: Located in the Public Subnet, it translates the Private IP to its Elastic IP.
4.  **Internet Gateway**: Sends traffic to the internet.

### 3. Administrative Access (SSH)
*Services involved: Bastion Host, TGW, TGW Attachments, Route Tables, Security Groups.*
1.  **Admin**: SSH into **Bastion Host** (in `VPC-Bastion`) via IGW.
2.  **Transit Gateway (TGW)**: Bastion sends traffic to the Private IP of the App Instance.
3.  **Route Table (Bastion)**: Route `172.32.0.0/16` points to the **TGW**.
4.  **TGW Attachments**: Traffic flows through the TGW attachment from `VPC-Bastion` to `VPC-App`.
5.  **Security Group (App SG)**: **Inbound Rule** allows Port 22 from the Bastion Subnet CIDR.
6.  **EC2 Instance**: Admin accesses the shell.

### 4. Infrastructure Lifecycle & Observability
*Services involved: Launch Template, ASG, VPC Flow Logs.*
*   **Auto Scaling Group (ASG)**: Monitors the health of instances. If an instance fails, it uses the **Launch Template** (which defines the AMI, Instance Type, SG, and User Data) to provision a new one.
*   **VPC Flow Logs**: Captures metadata about the IP traffic going to and from network interfaces (ENIs) in your VPCs, stored in CloudWatch Logs for analysis.

## 2. Prerequisites
- AWS Account with appropriate permissions.
- AWS CLI installed and configured locally.
- SSH Client.
- Git installed.

## 3. Implementation Tasks

### Phase 1: Pre-Deployment (Golden AMI)
**Objective**: Create a reusable AMI with all dependencies pre-installed.
1.  **Launch Temporary Instance**:
    - Launch an EC2 instance (Amazon Linux 2 or Ubuntu).
    - Ensure it has public internet access.
2.  **Install Dependencies**:
    - SSH into the instance.
    - Run the provided setup script or manually install:
        - AWS CLI
        - Apache Web Server (`httpd` or `apache2`)
        - Git
        - CloudWatch Agent
        - SSM Agent (usually pre-installed on AL2/Ubuntu)
3.  **Verify Configuration**:
    - Ensure Apache is running (`systemctl status httpd`).
    - Ensure CloudWatch agent is installed.
4.  **Create AMI**:
    - Select the instance in AWS Console -> Actions -> Image and templates -> Create image.
    - Name it `DevOps-Project-02-Golden-AMI`.
    - Terminate the temporary instance after AMI creation.

**Verification Criteria**:
- [ ] **AMI Availability** (Run Locally):
  ```bash
  aws ec2 describe-images --owners self --filters "Name=name,Values=DevOps-Project-02-Golden-AMI" --query 'Images[*].[ImageId,State,Name]' --output table
  ```
  *Expected Output*: Should show the AMI ID, State as `available`, and the correct Name.

### Phase 2: Network Infrastructure (VPC)
**Objective**: Set up the networking foundation.
1.  **Create VPCs**:
    - **Navigate to VPC Dashboard** -> **Your VPCs** -> **Create VPC**.
    - **VPC 1**: Name `DevOps-Project-02-VPC-Bastion`, CIDR `192.168.0.0/16`.
    - **VPC 2**: Name `DevOps-Project-02-VPC-App`, CIDR `172.32.0.0/16`.
2.  **Create Subnets**:
    - **Navigate to Subnets** -> **Create subnet**.
    - **VPC-Bastion**:
        - Name `Bastion-Public-Subnet`, CIDR `192.168.1.0/24`, AZ `us-east-1a`.
    - **VPC-App**:
        - Name `App-Private-Subnet-1`, CIDR `172.32.1.0/24`, AZ `us-east-1a`.
        - Name `App-Private-Subnet-2`, CIDR `172.32.2.0/24`, AZ `us-east-1b`.
        - Name `App-Public-Subnet-NAT`, CIDR `172.32.0.0/24`, AZ `us-east-1a`.
3.  **Gateways**:
    - **Internet Gateway (IGW)**:
        - **Navigate to Internet Gateways** -> **Create internet gateway**.
        - Name `DevOps-Project-02-IGW`.
        - **Attach** to `VPC-Bastion`.
        - *Repeat* to create another IGW for `VPC-App` (or use TGW for egress, but for simplicity, let's attach IGW to both for now or stick to the plan). *Correction*: Plan says IGW for both.
    - **NAT Gateway**:
        - **Navigate to NAT Gateways** -> **Create NAT gateway**.
        - Name `DevOps-Project-02-NAT`.
        - **Subnet**: Select `App-Public-Subnet-NAT`.
        - **Connectivity type**: Public.
        - **Elastic IP allocation ID**: Allocate Elastic IP.
4.  **Transit Gateway (TGW)**:
    - **Navigate to Transit Gateways** -> **Create Transit Gateway**.
    - Name `DevOps-Project-02-TGW`.
    - **Auto accept shared attachments**: Enable.
    - **Create TGW Attachments**:
        - **Navigate to Transit Gateway Attachments** -> **Create attachment**.
        - **TGW ID**: Select your TGW.
        - **Attachment type**: VPC.
        - **VPC ID**: Select `VPC-Bastion`. Subnet: `Bastion-Public-Subnet`.
        - *Repeat* for `VPC-App`. Subnets: Select both Private Subnets (or all).
5.  **Route Tables**:
    - **Navigate to Route Tables**.
    - **RT-Bastion-Public**:
        - Create RT, associate with `VPC-Bastion`.
        - **Routes**: `0.0.0.0/0` -> IGW (Bastion). `172.32.0.0/16` -> TGW.
        - **Subnet Associations**: `Bastion-Public-Subnet`.
    - **RT-App-Public** (for NAT):
        - Create RT, associate with `VPC-App`.
        - **Routes**: `0.0.0.0/0` -> IGW (App).
        - **Subnet Associations**: `App-Public-Subnet-NAT`.
    - **RT-App-Private**:
        - Create RT, associate with `VPC-App`.
        - **Routes**: `0.0.0.0/0` -> NAT GW. `192.168.0.0/16` -> TGW.
        - **Subnet Associations**: `App-Private-Subnet-1`, `App-Private-Subnet-2`.

6.  **Deploy Bastion Host**:
    - **Navigate to EC2** -> **Launch Instances**.
    - **Name**: `DevOps-Project-02-Bastion`.
    - **AMI**: Amazon Linux 2 or Ubuntu.
    - **Instance Type**: `t2.micro`.
    - **Key pair**: Select your existing key pair.
    - **Network settings**:
        - **VPC**: `VPC-Bastion`.
        - **Subnet**: `Public Subnet`.
        - **Auto-assign Public IP**: Enable.
        - **Security Group**: Select `Bastion SG`.
    - **Launch Instance**.

**Verification Criteria**:
- [ ] **Bastion Public IP** (Run Locally):
  ```bash
  aws ec2 describe-instances --filters "Name=tag:Name,Values=DevOps-Project-02-Bastion" --query 'Reservations[*].Instances[*].PublicIpAddress' --output text
  ```
  *Check*: Should return a Public IP address.
- [ ] **Route Table Association** (Run Locally):
  ```bash
  # List Route Tables and their associations
  aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-xxxxxxxx" --query 'RouteTables[*].{RT:RouteTableId, VpcId:VpcId, Routes:Routes, Associations:Associations}'
  ```
  *Check*: Ensure Public Subnets have routes to `igw-xxxx` and Private Subnets have routes to `nat-xxxx` or `tgw-xxxx`.
- [ ] **Transit Gateway Attachments** (Run Locally):
  ```bash
  aws ec2 describe-transit-gateway-attachments --filters "Name=state,Values=available" --query 'TransitGatewayAttachments[*].{ID:TransitGatewayAttachmentId, State:State, VpcId:ResourceId}'
  ```
  *Check*: Both VPCs should be listed as attached and `available`.

### Phase 3: Security & Logging
**Objective**: Secure the infrastructure and enable monitoring.
### Phase 3: Security & Logging
**Objective**: Secure the infrastructure and enable monitoring.
1.  **Security Groups (SG)**:
    - **Navigate to EC2** -> **Security Groups** -> **Create security group**.
    - **Bastion SG**:
        - Name `DevOps-Project-02-Bastion-SG`.
        - VPC: `DevOps-Project-02-VPC-Bastion`.
        - **Inbound Rules**:
            - Type: SSH, Protocol: TCP, Port: 22, Source: `0.0.0.0/0` (or `My IP`).
    - **App SG**:
        - Name `DevOps-Project-02-App-SG`.
        - VPC: `DevOps-Project-02-VPC-App`.
        - **Inbound Rules**:
            - Type: SSH, Protocol: TCP, Port: 22, Source: `192.168.1.0/24` (Bastion Subnet CIDR).
            - Type: HTTP, Protocol: TCP, Port: 80, Source: `0.0.0.0/0` (Allowing traffic from NLB/Internet).
2.  **IAM Roles**:
    - **Navigate to IAM** -> **Roles** -> **Create role**.
    - **Trusted entity type**: AWS service -> **Service or use case**: EC2.
    - **Add permissions**:
        - Search and select `AmazonSSMManagedInstanceCore`.
        - Search and select `CloudWatchAgentServerPolicy`.
        - *Optional*: Create inline policy for S3 Read Access if needed.
    - **Name**: `AppServerRole`.
    - **Create role**.
3.  **VPC Flow Logs**:
    - **Create Log Group**:
        - **Navigate to CloudWatch** -> **Logs** -> **Log groups** -> **Create log group**.
        - Name: `VPC-Flow-Logs`.
    - **Enable Flow Logs**:
        - **Navigate to VPC Dashboard** -> **Your VPCs**.
        - Select `DevOps-Project-02-VPC-Bastion` -> **Actions** -> **Create flow log**.
        - **Filter**: All.
        - **Destination**: Send to CloudWatch Logs.
        - **Destination log group**: `VPC-Flow-Logs`.
        - **IAM role**: Create a new role or select one with `vpc-flow-logs` permissions.
        - *Repeat* for `DevOps-Project-02-VPC-App`.

**Verification Criteria**:
- [ ] **Security Group Rules** (Run Locally):
  ```bash
  aws ec2 describe-security-groups --group-ids sg-xxxxxxxx --output text
  ```
  *Check*: Verify port 22/80 rules match the requirements.
- [ ] **IAM Role Policies** (Run Locally):
  ```bash
  aws iam list-attached-role-policies --role-name AppServerRole
  ```
  *Check*: Should list `AmazonSSMManagedInstanceCore` and `CloudWatchAgentServerPolicy`.
- [ ] **Flow Logs** (Run Locally):
  ```bash
  aws logs describe-log-groups --log-group-name-prefix VPC-Flow-Logs
  ```
  *Check*: Log Group should exist. Check AWS Console -> CloudWatch -> Log Groups to see incoming log streams.

### Phase 4: Application Deployment
**Objective**: Deploy the scalable web application.
1.  **S3 Bucket**:
    - Create a bucket (e.g., `devops-project-02-config-<yourname>`).
    - Upload `html-web-app` content (index.html, etc.) to the bucket.
2.  **Launch Configuration / Launch Template**:
    - **Navigate to EC2** -> **Launch Templates** -> **Create launch template**.
    - **Name**: `DevOps-Project-02-Template`.
    - **AMI**: Select "My AMIs" -> `DevOps-Project-02-Golden-AMI`.
    - **Instance Type**: `t2.micro`.
    - **Key pair**: Select your existing key pair.
    - **Network settings**: Select `App SG`.
    - **Advanced details**:
        - **IAM instance profile**: Select `AppServerRole`.
        - **User Data**: (Paste at the bottom)
          ```bash
          #!/bin/bash
          aws s3 cp s3://devops-project-02-config-hieuhn0301/ /var/www/html/ --recursive
          systemctl start httpd
          systemctl enable httpd
          ```
3.  **Target Group** (Create First):
    - **Navigate to EC2** -> **Target Groups** -> **Create target group**.
    - **Target type**: `Instances`.
    - **Target group name**: `DevOps-Project-02-TG`.
    - **Protocol**: `TCP` (NOT HTTP, because we are using a Network Load Balancer).
    - **Port**: `80`.
    - **VPC**: Select `VPC-App`.
    - **Health checks**: Keep defaults (TCP).
    - **Register targets**: Skip this step (ASG will do it automatically). Click **Create**.

4.  **Network Load Balancer (NLB)** (Create Second):
    - **Navigate to EC2** -> **Load Balancers** -> **Create load balancer**.
    - **Type**: **Network Load Balancer** -> Create.
    - **Name**: `DevOps-Project-02-NLB`.
    - **Scheme**: `Internet-facing`.
    - **IP address type**: `IPv4`.
    - **Network mapping**:
        - **VPC**: `VPC-App`.
        - **Mappings**: Select the **Public Subnet** in each Availability Zone.
    - **Listeners and routing**:
        - **Protocol**: `TCP`.
        - **Port**: `80`.
        - **Default action**: Forward to `DevOps-Project-02-TG`.
    - Click **Create load balancer**.

5.  **Auto Scaling Group (ASG)** (Create Last):
    - **Navigate to EC2** -> **Auto Scaling Groups** -> **Create Auto Scaling group**.
    - **Name**: `DevOps-Project-02-ASG`.
    - **Launch template**: Select `DevOps-Project-02-Template`.
    - **Network**:
        - **VPC**: `VPC-App`.
        - **Subnets**: Select the **Private Subnets** (e.g., `Private Subnet 1`, `Private Subnet 2`).
    - **Load balancing**:
        - Select **Attach to an existing load balancer**.
        - Choose **Choose from your load balancer target groups**.
        - Select `DevOps-Project-02-TG`.
    - **Group size**:
        - Desired capacity: `2`.
        - Minimum capacity: `2`.
        - Maximum capacity: `4`.
    - **Review and Create**.

**Verification Criteria**:
- [ ] **ASG Instances** (Run Locally):
  ```bash
  aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names YOUR_ASG_NAME --query 'AutoScalingGroups[*].Instances[*].{ID:InstanceId, Health:HealthStatus, State:LifecycleState}'
  ```
  *Check*: Should show 2 instances with Health `Healthy` and State `InService`.
- [ ] **Target Group Health** (Run Locally):
  ```bash
  aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:region:account:targetgroup/name/id
  ```
  *Check*: TargetHealth.State should be `healthy`.
- [ ] **NLB Access** (Run Locally):
  ```bash
  # Find DNS Name in AWS Console -> EC2 -> Load Balancers -> Select NLB -> Description -> DNS name
  curl -I http://YOUR-NLB-DNS-NAME
  ```
  *Check*: Should return `HTTP/1.1 200 OK`.

### Phase 5: Final Validation
1.  **Public Access** (Run Locally):
    Find DNS Name in AWS Console -> EC2 -> Load Balancers -> Select NLB -> Description -> DNS name
    ```bash
    curl http://YOUR-NLB-DNS-NAME
    ```
    *Expected*: Returns the HTML content of your web app.
2.  **Bastion Access** (Run Locally -> Bastion):
    ```bash
    ssh -i key.pem ec2-user@BASTION_PUBLIC_IP
    # From Bastion:
    ssh -i key.pem ec2-user@PRIVATE_INSTANCE_IP
    ```
    *Expected*: Successful login to private instance.
3.  **Session Manager** (Run Locally):
    ```bash
    aws ssm start-session --target i-xxxxxxxxxxxx
    ```
    *Expected*: Opens a shell session to the instance.
4.  **Auto Scaling** (Run Locally):
    ```bash
    aws autoscaling terminate-instance-in-auto-scaling-group --instance-id i-xxxxxxxx --no-should-decrement-desired-capacity
    ```
    *Expected*: ASG should launch a new instance to replace the terminated one. Verify with `aws autoscaling describe-auto-scaling-groups`.

## 4. Troubleshooting Guide
- **Instance not healthy?** Check User Data logs (`/var/log/cloud-init-output.log`) and SG rules.
- **Cannot SSH?** Check Route Tables and TGW routes.
- **Page not loading?** Check Apache status and S3 permissions.