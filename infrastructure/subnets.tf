resource "aws_subnet" "public_subnet" {
  for_each = var.public_subnet_cidr
  vpc_id   = aws_vpc.production_vpc.id

  # assigns a public ip to instances launched in the subnet
  map_public_ip_on_launch = true
  # maps the 2 azs to this subnet
  availability_zone = each.value.az
  # maps 2 cidr's to this cidr block
  cidr_block = each.value.cidr

  tags = {
    Name = "${var.project_name}-public-${each.key}"
    #lets eks put load balancers
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "eks_subnet" {
  for_each          = var.eks_subnet_cidr
  vpc_id            = aws_vpc.production_vpc.id
  availability_zone = each.value.az
  cidr_block        = each.value.cidr

  tags = {
    Name                              = "${var.project_name}-eks-${each.key}"
    "kubernetes.io/role/internal-elb" = 1
  }
}

resource "aws_subnet" "db_subnet" {
  for_each          = var.db_subnet_cidr
  vpc_id            = aws_vpc.production_vpc.id
  availability_zone = each.value.az
  cidr_block        = each.value.cidr

  tags = {
    Name = "${var.project_name}-db-${each.key}"
  }
}
