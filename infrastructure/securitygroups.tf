# eks security group not needed as it creates its own when spun up
resource "aws_security_group" "db_sg" {
  vpc_id      = aws_vpc.production_vpc.id
  name        = "${var.project_name}-db-sg"
  description = "PostgreSQL: Only reachable from EKS node only"
  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

#BEFORE eks creation and after db creation

# resource "aws_vpc_security_group_ingress_rule" "vpc_db_sg_ingress" {
#   for_each          = aws_subnet.eks_subnet
#   security_group_id = aws_security_group.db_sg.id
#   cidr_ipv4         = each.value.cidr_block
#   from_port         = 5432
#   to_port           = 5432
#   ip_protocol       = "tcp"
# }



# AFTER EKS CREATION
/*
The weakness: anything that ever gets an IP in those subnets can reach the database, for example an internal load balancer,
a network interface from another service, or a misplaced resource. The rule trusts a location, not an identity.

Better: allow 5432 only from things that have the EKS cluster security group, which is exactly your nodes (and their pods):
https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html
*/
resource "aws_vpc_security_group_ingress_rule" "vpc_db_sg_ingress" {
  security_group_id            = aws_security_group.db_sg.id
  referenced_security_group_id = aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}