resource "aws_db_subnet_group" "main" {
  name_prefix = "rakazo-"
  subnet_ids  = aws_subnet.database[*].id
}

# Plain PostgreSQL, not Aurora Serverless: Prisma and Graphile Worker keep long
# LISTEN connections and Serverless v2 scaling pauses would add latency.
resource "aws_db_instance" "main" {
  identifier_prefix = "rakazo-"

  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  db_name  = "rakazo"
  username = "rakazo"
  # RDS creates and rotates the password in Secrets Manager. The host reads it
  # at boot, so it never appears in Terraform state or user data.
  manage_master_user_password = true

  allocated_storage = var.db_allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true

  multi_az               = var.db_multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  availability_zone      = var.db_multi_az ? null : local.azs[0]

  backup_retention_period    = var.db_backup_retention_days
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true
  deletion_protection        = var.db_deletion_protection
  skip_final_snapshot        = false
  final_snapshot_identifier  = "rakazo-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}
