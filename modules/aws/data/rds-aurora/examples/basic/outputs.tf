output "cluster_arn" {
  description = "ARN of the Aurora cluster."
  value       = module.rds_aurora.cluster_arn
}

output "endpoint" {
  description = "Writer endpoint of the cluster."
  value       = module.rds_aurora.endpoint
}

output "reader_endpoint" {
  description = "Load-balanced reader endpoint of the cluster."
  value       = module.rds_aurora.reader_endpoint
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret holding the master credentials."
  value       = module.rds_aurora.master_user_secret_arn
}
