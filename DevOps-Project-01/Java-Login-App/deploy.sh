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