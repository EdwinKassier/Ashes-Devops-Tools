output "service_name" {
  description = "Name of the ECS service."
  value       = local.service.name
}

output "service_arn" {
  description = "ARN of the ECS service."
  value       = local.service.id
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

output "task_definition_family" {
  description = "Family of the task definition (CI registers new revisions in this family)."
  value       = aws_ecs_task_definition.this.family
}

output "container_name" {
  description = "Name of the primary container (the container CI rewrites the image of)."
  value       = local.container_name
}
