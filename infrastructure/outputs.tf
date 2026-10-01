output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.production_vpc.id
}

output "vpc_cidr_block" {
  description = "IP range of the VPC"
  value       = aws_vpc.production_vpc.cidr_block
}

output "aws_public_subnet_ids" {
  description = "ID of the public subnets"
  value       = [for s in aws_subnet.public_subnet : s.id]
}

output "aws_eks_subnet" {
  description = "ID of the eks subnets"
  value       = [for s in aws_subnet.eks_subnet : s.id]
}

output "aws_db_subnet" {
  description = "ID for the db subnets"
  value       = [for s in aws_subnet.db_subnet : s.id]
}

output "eks_cluster_name" {
  value = aws_eks_cluster.cluster.name
}

output "kubeconfig_cmd" {
  value = "aws eks update-kubeconfig --name ${aws_eks_cluster.cluster.name} --region ${var.aws_region}"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.learning-steps-repository.repository_url
}

output "rds_endpoint" {
  value = aws_db_instance.db.address
}

output "db_secret_arn" {
  value = aws_db_instance.db.master_user_secret[0].secret_arn
}

output "app_role_arn" {
  value = aws_iam_role.app.arn
}


