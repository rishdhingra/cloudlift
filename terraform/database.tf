resource "aws_db_subnet_group" "cloudlift" {
  name       = "${var.project_name}-db"
  subnet_ids = [aws_subnet.private_db_a.id, aws_subnet.private_db_b.id]
}

resource "aws_cloudwatch_log_group" "database" {
  name              = "/aws/rds/instance/${var.project_name}-demo/postgresql"
  retention_in_days = 3
}
resource "aws_db_instance" "cloudlift" {
  depends_on                          = [aws_cloudwatch_log_group.database]
  identifier                          = "${var.project_name}-demo"
  engine                              = "postgres"
  engine_version                      = "16"
  instance_class                      = "db.t4g.small"
  allocated_storage                   = 20
  storage_type                        = "gp3"
  storage_encrypted                   = true
  multi_az                            = true
  db_name                             = "cloudlift"
  username                            = "cloudlift_admin"
  manage_master_user_password         = true
  iam_database_authentication_enabled = true
  db_subnet_group_name                = aws_db_subnet_group.cloudlift.name
  vpc_security_group_ids              = [aws_security_group.database.id]
  publicly_accessible                 = false
  backup_retention_period             = 1
  delete_automated_backups            = true
  skip_final_snapshot                 = true
  deletion_protection                 = false
  copy_tags_to_snapshot               = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  performance_insights_enabled        = false
  apply_immediately                   = true
  tags                                = { Project = var.project_name, Purpose = "temporary-resume-demo" }
}
