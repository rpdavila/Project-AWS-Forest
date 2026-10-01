# routes all traffic to the gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.production_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# associates the route table to the subnet.
resource "aws_route_table_association" "rta" {
  for_each       = aws_subnet.public_subnet
  route_table_id = aws_route_table.public.id
  subnet_id      = each.value.id
}

resource "aws_route_table" "eks-rt" {
  vpc_id   = aws_vpc.production_vpc.id
  for_each = aws_subnet.eks_subnet
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ng[each.key].id
  }

  tags = {
    Name = "${var.project_name}-eks-rt-${each.key}"
  }
}

resource "aws_route_table_association" "eks-nat-association" {
  for_each       = aws_subnet.eks_subnet
  route_table_id = aws_route_table.eks-rt[each.key].id
  subnet_id      = each.value.id

}

resource "aws_route_table" "db_rt" {
  vpc_id = aws_vpc.production_vpc.id
  tags = {
    Name = "${var.project_name}-db-rt"
  }
}

resource "aws_route_table_association" "db_rt_association" {
  route_table_id = aws_route_table.db_rt.id
  for_each       = aws_subnet.db_subnet
  subnet_id      = each.value.id


}