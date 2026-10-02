resource "aws_db_instance" "db" {
  identifier                  = "${var.project_name}-postgres"
  engine                      = "postgres"
  engine_version              = "18.6"
  instance_class              = "db.t3.micro"
  allocated_storage           = 20
  storage_encrypted           = true # uses aws kms
  db_subnet_group_name        = aws_db_subnet_group.db.name
  username                    = "learningsteps"
  manage_master_user_password = true # uses aws kms
  db_name                     = "learning_journal"
  multi_az                    = true
  vpc_security_group_ids      = [aws_security_group.db_sg.id]
  publicly_accessible         = false
  storage_type                = "gp3"
  skip_final_snapshot         = true  # lab: no snapshot on destroy
  deletion_protection         = false # lab: allow destroy
  backup_retention_period     = 1     # keep 1 day of automatic backups
  apply_immediately           = true  # lab: don't wait for maintenance window
  tags = {
    Name = "${var.project_name}-postgres"
  }
}

# needed for the db subnet group name
resource "aws_db_subnet_group" "db" {
  name       = "${var.project_name}-db-subnetgroup"
  subnet_ids = [for s in aws_subnet.db_subnet : s.id]
  tags = {
    Name = "${var.project_name}-db-subnetgroup"
  }
}