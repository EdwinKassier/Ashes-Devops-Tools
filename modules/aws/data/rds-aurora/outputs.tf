output "cluster_arn" {
  description = "ARN of the Aurora cluster."
  value       = aws_rds_cluster.this.arn
}

output "cluster_identifier" {
  description = "Identifier of the Aurora cluster."
  value       = aws_rds_cluster.this.cluster_identifier
}

output "endpoint" {
  description = "Writer (primary) endpoint of the cluster."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint of the cluster (load-balances across replicas)."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "Port the database listens on."
  value       = aws_rds_cluster.this.port
}

output "database_name" {
  description = "Name of the initial database."
  value       = aws_rds_cluster.this.database_name
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed master user secret in Secrets Manager. Null when manage_master_user_password is false."
  value       = var.manage_master_user_password ? try(aws_rds_cluster.this.master_user_secret[0].secret_arn, null) : null
}

output "instance_identifiers" {
  description = "Identifiers of the cluster instances (writer + readers)."
  value       = aws_rds_cluster_instance.this[*].identifier
}
