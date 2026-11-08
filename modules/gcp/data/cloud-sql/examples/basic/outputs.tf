output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = module.cloud_sql.name
}

output "connection_name" {
  description = "Connection name for the Cloud SQL Auth Proxy / connectors."
  value       = module.cloud_sql.connection_name
}

output "private_ip_address" {
  description = "Private IPv4 address of the instance."
  value       = module.cloud_sql.private_ip_address
  sensitive   = true
}
