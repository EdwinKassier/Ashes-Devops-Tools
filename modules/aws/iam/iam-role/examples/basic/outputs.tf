output "role_arns" {
  description = "Map of workload role name to role ARN."
  value       = module.iam_role.role_arns
}

output "break_glass_role_arn" {
  description = "ARN of the break-glass role."
  value       = module.iam_role.break_glass_role_arn
}
