output "ecs_cluster_name" {
  description = "Name of the shared ECS cluster."
  value       = module.app_services.ecs_cluster_name
}

output "alb_dns_name" {
  description = "DNS name of the shared internal ALB."
  value       = module.app_services.alb_dns_name
}

output "services" {
  description = "Per-service deploy contract (ECR URL, deploy role, task-definition family, ...) for CI."
  value       = module.app_services.services
}

output "alarm_topic_arn" {
  description = "ARN of the SNS topic receiving the services' alarm notifications."
  value       = module.app_services.alarm_topic_arn
}
