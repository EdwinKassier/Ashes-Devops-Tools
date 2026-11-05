/**
 * Copyright 2023 Ashes
 *
 * Cloud SQL (PostgreSQL) Module - Outputs
 */

output "name" {
  description = "The name of the Cloud SQL instance"
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "The connection name of the instance, used by the Cloud SQL Auth Proxy (<project>:<region>:<name>)"
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "The private IPv4 address assigned to the instance"
  value       = google_sql_database_instance.this.private_ip_address
  sensitive   = true
}

output "self_link" {
  description = "The URI of the Cloud SQL instance"
  value       = google_sql_database_instance.this.self_link
}
