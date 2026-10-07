# Stores Terraform state in S3 instead of a local terraform.tfstate file.
# Note: backend blocks can't use variables, so values are written out here.
terraform {
  backend "s3" {
    bucket = "rafael-forestproject-tfstate-518285921450"
    key    = "rpdavila/learning-steps/prod/rafael.tfstate" # own folder: the bucket is shared
    region = "eu-central-1"

    encrypt      = true # encrypt the state file at rest
    use_lockfile = true # S3-native locking (no DynamoDB table needed)
  }
}
