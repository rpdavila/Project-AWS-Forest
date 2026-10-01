# use s3 endpoint for eks nodes
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.production_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for s in aws_route_table.eks-rt : s.id]
  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}

