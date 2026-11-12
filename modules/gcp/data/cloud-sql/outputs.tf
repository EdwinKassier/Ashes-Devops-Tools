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

output "public_ip_enabled" {
  description = "Whether the instance has a public IPv4 address. Always false: the module is private-IP only."
  value       = google_sql_database_instance.this.settings[0].ip_configuration[0].ipv4_enabled
}

output "private_network" {
  description = "The VPC network the instance is peered into via Private Service Access."
  value       = google_sql_database_instance.this.settings[0].ip_configuration[0].private_network
}

output "availability_type" {
  description = "REGIONAL (high availability, synchronous standby in a second zone) or ZONAL."
  value       = google_sql_database_instance.this.settings[0].availability_type
}

output "backup_location" {
  description = "Location of the automated backups: backup_location, else the instance region."
  value       = coalesce(var.backup_location, var.region)
}

output "encryption_key_name" {
  description = "The customer-managed key that encrypts the instance, or null for Google-managed encryption."
  value       = var.encryption_key_name
}

output "cmek_required" {
  description = "True when require_cmek is set, so the plan fails without a customer-managed key."
  value       = var.require_cmek
}
