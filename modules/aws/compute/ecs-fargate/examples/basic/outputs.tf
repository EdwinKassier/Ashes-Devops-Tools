output "service_name" {
  description = "Name of the ECS service."
  value       = module.ecs_fargate.service_name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster the service runs in."
  value       = module.ecs_fargate.cluster_arn
}

output "task_definition_family" {
  description = "Task-definition family CI registers new revisions in."
  value       = module.ecs_fargate.task_definition_family
}

output "log_group_name" {
  description = "CloudWatch log group receiving container logs."
  value       = module.ecs_fargate.log_group_name
}
