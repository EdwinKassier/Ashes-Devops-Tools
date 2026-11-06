output "ecs_cluster_name" {
  description = "Name of the shared per-environment ECS cluster, or null when services is empty."
  value       = local.enabled ? aws_ecs_cluster.this[0].name : null
}

output "ecs_cluster_arn" {
  description = "ARN of the shared per-environment ECS cluster, or null when services is empty."
  value       = try(aws_ecs_cluster.this[0].arn, null)
}

output "alb_arn" {
  description = "ARN of the shared ALB, or null when services is empty."
  value       = try(module.alb[0].arn, null)
}

output "alb_dns_name" {
  description = "DNS name of the shared ALB (internal by default), or null when services is empty."
  value       = try(module.alb[0].dns_name, null)
}

output "alb_internal" {
  description = "Whether the shared ALB is internal, or null when services is empty."
  value       = try(module.alb[0].internal, null)
}

output "alb_zone_id" {
  description = "Route 53 hosted zone ID of the shared ALB (for alias records), or null when services is empty."
  value       = try(module.alb[0].zone_id, null)
}

output "alb_security_group_id" {
  description = "Security group of the shared ALB, or null when services is empty."
  value       = try(module.alb[0].security_group_id, null)
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider deploy roles trust (created here or passed in), or null when enable_github_oidc is false."
  value       = var.enable_github_oidc ? local.github_oidc_provider_arn : null
}

output "github_oidc_subjects" {
  description = "Map of service name to the exact token.actions.githubusercontent.com:sub its deploy role trusts."
  value       = local.github_subjects
}

output "services" {
  description = "Per-service deployment contract: everything a CI pipeline needs (ECR repo, deploy role, cluster/service, task-definition family, container name) plus the runtime roles, log group and optional database endpoint/secret."
  value = {
    for k, s in var.services : k => {
      ecr_repository_url     = module.ecr[0].repository_urls[k]
      ecr_repository_name    = k
      deploy_role_arn        = try(aws_iam_role.deploy[k].arn, null)
      ecs_cluster_name       = local.cluster_name
      ecs_service_name       = module.service[k].service_name
      task_definition_family = module.service[k].task_definition_family
      container_name         = module.service[k].container_name
      initial_image          = local.svc[k].initial_image
      execution_role_arn     = aws_iam_role.execution[k].arn
      task_role_arn          = aws_iam_role.task[k].arn
      log_group_name         = aws_cloudwatch_log_group.service[k].name
      security_group_id      = aws_security_group.service[k].id
      database_endpoint      = try(module.database[k].endpoint, null)
      database_secret_arn    = try(module.database[k].master_user_secret_arn, null)
      database_public        = try(module.database[k].publicly_accessible, null)
    }
  }
}

output "kms_key_arn" {
  description = "CMK encrypting every service's ECR repository, log group, Aurora cluster and RDS master secret, or null when services is empty."
  value       = local.enabled ? var.kms_key_arn : null
}
