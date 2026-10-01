resource "aws_eip" "nat" {
  for_each = aws_subnet.public_subnet
  domain   = "vpc"
  tags = {
    Name = "${var.project_name}-nat-eip-${each.key}"
  }
}

resource "aws_nat_gateway" "ng" {
  for_each      = aws_subnet.public_subnet
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    Name = "${var.project_name}-nat-${each.key}"
  }
}

