variable "environment" {
  description = "Environment name"
  type        = string
}

variable "rds_instance_id" {
  description = "RDS instance ID for monitoring"
  type        = string
}

variable "asg_name" {
  description = "Auto Scaling Group name for monitoring"
  type        = string
}

variable "sns_email" {
  description = "Email address for SNS notifications"
  type        = string
  default     = ""
}