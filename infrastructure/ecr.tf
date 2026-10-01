resource "aws_ecr_repository" "learning-steps-repository" {
  name                 = "${var.project_name}/learningsteps"
  image_tag_mutability = "IMMUTABLE"

  #aws version of trivy, scan the docker image
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256" #default value
  }
  force_delete = true #terraform destroys image for lab env

  tags = {
    Name = "${var.project_name}-ecr"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.learning-steps-repository.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 10 images"
        selection = {
          tagStatus   = "any" # ← every image, whatever its tag (fixes the "v" bug)
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}