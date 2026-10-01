# Create a VPC
resource "aws_vpc" "production_vpc" {
  cidr_block = var.vpc_cidr

  # Needed so resources get DNS names (e.g. RDS endpoints, EC2 public hostnames)
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}


