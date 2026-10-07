variable "aws_region" {
  type        = string
  description = "AWS region to deploy into"
  default     = "eu-central-1"
}

variable "project_name" {
  type        = string
  description = "Short name used as a prefix for resource names"
  default     = "rafael-forestproject"
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g. dev, prod)"
  default     = "prod"
}

variable "vpc_cidr" {
  type        = string
  description = "IP range for the VPC"
  default     = "10.0.0.0/16"
}

# maps the cidr for the subnets to the az's
variable "public_subnet_cidr" {
  type        = map(object({ cidr = string, az = string }))
  description = "public subnet cidr"
  default = {
    a = { cidr = "10.0.1.0/24", az = "eu-central-1a" }
    b = { cidr = "10.0.2.0/24", az = "eu-central-1b" }
  }
}

variable "eks_subnet_cidr" {
  type        = map(object({ cidr = string, az = string }))
  description = "private subnet for eks"
  default = {
    a = { cidr = "10.0.11.0/24", az = "eu-central-1a" },
    b = { cidr = "10.0.12.0/24", az = "eu-central-1b" }
  }
}

variable "db_subnet_cidr" {
  type        = map(object({ cidr = string, az = string }))
  description = "private subnet for db"
  default = {
    a = { cidr = "10.0.24.0/24", az = "eu-central-1a" },
    b = { cidr = "10.0.25.0/24", az = "eu-central-1b" }
  }
}

variable "my_ip_cidr" {
  type        = string
  description = "My Public IP (/32)"
}

