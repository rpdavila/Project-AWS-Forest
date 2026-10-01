resource "aws_eks_cluster" "cluster" {
  name     = "${var.project_name}-eks-cluster"
  version  = "1.36"
  role_arn = aws_iam_role.eks_service_role.arn
  vpc_config {
    subnet_ids = [for s in aws_subnet.eks_subnet : s.id]
    public_access_cidrs = [
      var.my_ip_cidr
      #"github-runers-IP's"
    ]
    endpoint_private_access = true # for private node communication
    endpoint_public_access  = true # for communication from kubectl
  }
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true #explicit not dependant on defaults
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_service_role_policy,
    aws_cloudwatch_log_group.eks_cluster_logs
  ]
  enabled_cluster_log_types = ["api", "audit", "authenticator"] # send logs to cloudwatch
  tags = {
    Name = "${var.project_name}-eks-cluster"
  }
}

resource "aws_eks_node_group" "eks_node_group" {
  node_group_name = "${var.project_name}-nodegroup"
  cluster_name    = aws_eks_cluster.cluster.name
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = [for s in aws_subnet.eks_subnet : s.id]
  instance_types  = ["t3.medium"]
  disk_size       = 30
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND" # ON_DEMAND = stable; SPOT = cheaper for labs
  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }
  update_config {
    max_unavailable = 1 # during update only 1 node updates at a time
  }

  depends_on = [aws_iam_role_policy_attachment.eks_nodes_policy]

  tags = {
    Name = "${var.project_name}-eks-node-group"
  }
}

resource "aws_cloudwatch_log_group" "eks_cluster_logs" {
  name              = "/aws/eks/${var.project_name}-eks-cluster/cluster"
  retention_in_days = 7
  tags = {
    Name = "${var.project_name}-eks-cluster-log-group"
  }
}

# Hands out AWS credentials to specific pods
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name  = aws_eks_cluster.cluster.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = "v1.3.10-eksbuild.3"
  depends_on    = [aws_eks_node_group.eks_node_group]
  tags = {
    Name = "${var.project_name}-eks-pod-identity-agent"
  }
}

# The Secrets Store CSI driver + AWS provider (ASCP): mounts secrets from Secrets Manager into pods
resource "aws_eks_addon" "secret_store" {
  cluster_name  = aws_eks_cluster.cluster.name
  addon_name    = "aws-secrets-store-csi-driver-provider"
  addon_version = "v3.1.4-eksbuild.1"
  depends_on    = [aws_eks_node_group.eks_node_group]
  tags = {
    Name = "${var.project_name}-eks-secret-store"
  }
}


resource "aws_eks_pod_identity_association" "pod_identity_association" {
  cluster_name    = aws_eks_cluster.cluster.name
  namespace       = "learningsteps"
  service_account = "learningsteps-api"
  role_arn        = aws_iam_role.app.arn
}