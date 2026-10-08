resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags = {
    Name = "${var.project_name}-oidc"
  }
}

resource "aws_iam_role" "oidc_role" {
  name = "${var.project_name}-oidc-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action = [
        "sts:AssumeRoleWithWebIdentity"
      ]
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:rpdavila/Project-AWS-Forest:ref:refs/heads/master"
        }
      }
    }]
  })
  tags = {
    Name = "${var.project_name}-oidc-role"
  }
}

resource "aws_iam_role_policy" "oidc_role_policy" {
  name = "${var.project_name}-oidc-role-policy"
  role = aws_iam_role.oidc_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ecr:GetAuthorizationToken"]
      Resource = ["*"]
      }, {
      Effect = "Allow"
      Action = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ]
      Resource = aws_ecr_repository.learning-steps-repository.arn
    }]
  })
}