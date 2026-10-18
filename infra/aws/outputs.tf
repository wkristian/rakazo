output "url" {
  value = "https://${var.domain_name}"
}

output "instance_id" {
  description = "Open a shell with: aws ssm start-session --target <instance_id>"
  value       = aws_instance.app.id
}

output "database_endpoint" {
  value = aws_db_instance.main.address
}
