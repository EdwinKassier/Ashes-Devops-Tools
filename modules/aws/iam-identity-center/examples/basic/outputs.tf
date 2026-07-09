output "permission_set_arns" {
  description = "Map of permission set name to ARN created by the module."
  value       = module.iam_identity_center.permission_set_arns
}

output "instance_arn" {
  description = "ARN of the discovered Identity Center instance."
  value       = module.iam_identity_center.instance_arn
}
