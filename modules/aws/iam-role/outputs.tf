output "role_arns" {
  description = "Map of role name to role ARN for the roles created from var.roles."
  value       = { for name, role in aws_iam_role.this : name => role.arn }
}

output "break_glass_role_arn" {
  description = "ARN of the break-glass role, or null when enable_break_glass is false."
  value       = try(aws_iam_role.break_glass[0].arn, null)
}
