terraform {
  backend "s3" {
    bucket         = "my-ews-baket1"
    region         = "us-east-1"
    key            = "DevOps-Project-11/terraform.tfstate"
    dynamodb_table = "Lock-Files"
    encrypt        = true
  }
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      version = ">= 5.0.0"
      source  = "hashicorp/aws"
    }
  }
}
