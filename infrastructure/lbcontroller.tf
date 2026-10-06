resource "aws_iam_policy" "lb_controller" {
  name   = "${var.project_name}-lb-controller-policy"
  policy = file("${path.module}/policies/aws-lb-controller-v3.5.0.json")

  tags = {
    Name = "${var.project_name}-lb-controller-policy"
  }
}

resource "aws_iam_role" "lb_controller" {
  name = "${var.project_name}-lb-controller-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })
  tags = {
    Name = "${var.project_name}-lb-controller-role"
  }
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = aws_eks_cluster.cluster.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller.arn
}