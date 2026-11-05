output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.this.name
}

output "service_arn" {
  description = "ARN of the ECS service."
  value       = aws_ecs_service.this.id
}

output "task_definition_arn" {
  description = "ARN of the task definition revision the service runs."
  value       = aws_ecs_task_definition.this.arn
}

output "cluster_arn" {
  description = "ARN of the cluster the service runs in (created here or passed in)."
  value       = local.cluster_arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group container logs are shipped to."
  value       = local.log_group_name
}
