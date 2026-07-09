# Identity cross-root contract. Downstream tooling can read the permission set
# ARNs and the discovered Identity Center instance ARN. Keep keys stable across
# refactors — renaming a key breaks any root that reads it.

output "permission_set_arns" {
  description = "Map of permission set name to its ARN."
  value       = module.iam_identity_center.permission_set_arns
}

output "identity_center_instance_arn" {
  description = "ARN of the discovered (out-of-band) IAM Identity Center instance the permission sets and assignments are managed within."
  value       = module.iam_identity_center.instance_arn
}
