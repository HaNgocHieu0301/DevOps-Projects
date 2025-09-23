#!/bin/bash
# User data script for Java application server

# Log everything
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting user data script execution at $(date)"

# Update system
yum update -y

# Install Java 8 and required packages
yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel
yum install -y wget curl unzip amazon-ssm-agent

# Start and enable SSM agent
systemctl start amazon-ssm-agent
systemctl enable amazon-ssm-agent

# Install Tomcat 9
cd /opt
echo "Downloading Tomcat..."
wget https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.64/bin/apache-tomcat-9.0.64.tar.gz
tar xzf apache-tomcat-9.0.64.tar.gz
mv apache-tomcat-9.0.64 tomcat
rm apache-tomcat-9.0.64.tar.gz

# Create tomcat user
useradd -M -s /bin/nologin tomcat
chown -R tomcat: /opt/tomcat

# Set JAVA_HOME and environment variables
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
export CATALINA_HOME=/opt/tomcat
echo 'export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk' >> /etc/environment
echo 'export CATALINA_HOME=/opt/tomcat' >> /etc/environment

# Create systemd service for Tomcat
cat > /etc/systemd/system/tomcat.service << EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
Environment=JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
Environment=CATALINA_PID=/opt/tomcat/temp/tomcat.pid
Environment=CATALINA_HOME=/opt/tomcat
Environment=CATALINA_BASE=/opt/tomcat
Environment='CATALINA_OPTS=-Xms512M -Xmx1024M -server'
Environment='JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom'

ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh

User=tomcat
Group=tomcat
UMask=0007
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Create CloudWatch agent config
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "root"
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/opt/tomcat/logs/catalina.out",
                        "log_group_name": "/aws/tomcat/${environment}",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "CWAgent",
        "metrics_collected": {
            "mem": {
                "measurement": ["mem_used_percent"]
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            }
        }
    }
}
EOF

# Create health check endpoint first
echo "Creating health check endpoint..."
mkdir -p /opt/tomcat/webapps/ROOT
echo '<html><body><h1>Health Check OK</h1><p>Server is running at $(date)</p></body></html>' > /opt/tomcat/webapps/ROOT/index.html
chown -R tomcat: /opt/tomcat/webapps/

# Start and enable services
echo "Starting services..."
systemctl daemon-reload
systemctl enable tomcat
systemctl start tomcat

# Wait for Tomcat to start
echo "Waiting for Tomcat to start..."
sleep 10

# Check if Tomcat is running
systemctl status tomcat
netstat -tlnp | grep 8080

# Skip CloudWatch agent for now (to simplify troubleshooting)
# systemctl enable amazon-cloudwatch-agent
# /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

echo "User data script completed at $(date)"

# Set up log rotation
cat > /etc/logrotate.d/tomcat << EOF
/opt/tomcat/logs/catalina.out {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 644 tomcat tomcat
    postrotate
        systemctl reload tomcat
    endscript
}
EOF