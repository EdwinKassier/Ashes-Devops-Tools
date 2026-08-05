output "permission_set_arns" {
  description = "Map of permission set name to its ARN."
  value       = { for name, ps in aws_ssoadmin_permission_set.this : name => ps.arn }
}

output "instance_arn" {
  description = "The ARN of the discovered (out-of-band) IAM Identity Center instance these permission sets and assignments are managed within."
  value       = local.instance_arn
}
