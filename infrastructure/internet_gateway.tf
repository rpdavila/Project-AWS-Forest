resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.production_vpc.id
  tags = {
    Name = "${var.project_name}-igw"
  }
}