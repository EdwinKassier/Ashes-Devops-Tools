# Workload root outputs. Consumed for cross-account references and operator
# convenience; not a stable cross-root contract like the network root's.

output "vpc_id" {
  description = "The ID of the workload spoke VPC."
  value       = module.aws_workload.vpc_id
}

output "workload_role_arns" {
  description = "Map of workload IAM role name to role ARN."
  value       = module.aws_workload.workload_role_arns
}

output "saas_secret_arn" {
  description = "ARN of the bridged Supabase connection secret in Secrets Manager, or null when enable_saas_secret_bridge is false. Point the ECS task definition's container secret valueFrom at this ARN."
  value       = var.enable_saas_secret_bridge ? aws_secretsmanager_secret.saas_bridge[0].arn : null
}
