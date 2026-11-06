output "plan_role_arns" {
  description = "Workspace name => management-account PLAN role ARN (TFC_AWS_PLAN_ROLE_ARN)."
  value       = { for k, r in local.roles : r.workspace => aws_iam_role.this[k].arn if r.phase == "plan" }
}

output "apply_role_arns" {
  description = "Workspace name => management-account APPLY role ARN (TFC_AWS_APPLY_ROLE_ARN)."
  value       = { for k, r in local.roles : r.workspace => aws_iam_role.this[k].arn if r.phase == "apply" }
}

output "apply_policies" {
  description = "Workspace name => rendered apply-role inline policy JSON (evidence and review)."
  value       = local.apply_policies
}
