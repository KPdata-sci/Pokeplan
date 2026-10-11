# Postgres 16 for Dagster run history and Metabase settings. The pipeline's data
# lives in S3/Iceberg, not here. RDS creates and rotates the master password in
# Secrets Manager; a bootstrap migration creates separate dagster and metabase
# users and databases.

resource "aws_kms_key" "db" {
  description         = "${var.name} RDS"
  enable_key_rotation = true
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.data_subnet_ids
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-pg16"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  parameter {
    name  = "log_connections"
    value = "1"
  }
}

resource "aws_db_instance" "this" {
  identifier                          = var.name
  engine                              = "postgres"
  engine_version                      = "16"
  instance_class                      = var.db_instance_class
  allocated_storage                   = 20
  max_allocated_storage               = 100
  storage_type                        = "gp3"
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.db.arn
  db_name                             = "pokeplan"
  username                            = "pokeplan_admin"
  manage_master_user_password         = true
  iam_database_authentication_enabled = true
  multi_az                            = var.db_multi_az
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = [aws_security_group.db.id]
  parameter_group_name                = aws_db_parameter_group.this.name
  publicly_accessible                 = false
  backup_retention_period             = 7
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = !var.deletion_protection
  final_snapshot_identifier           = var.deletion_protection ? "${var.name}-final" : null
  auto_minor_version_upgrade          = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
}
