output "stack_set_name" {
  description = "Name of the SERVICE_MANAGED StackSet that deploys the TFC OIDC baseline."
  value       = aws_cloudformation_stack_set.this.name
}

output "stack_set_arn" {
  description = "ARN of the StackSet."
  value       = aws_cloudformation_stack_set.this.arn
}

output "stack_set_instance_ids" {
  description = "Map of targeted OU name -> stack set instance ID."
  value       = { for k, i in aws_cloudformation_stack_set_instance.this : k => i.id }
}

output "oidc_provider_url" {
  description = "Issuer URL of the IAM OIDC provider created in each targeted member account."
  value       = "https://${var.tfc_hostname}"
}

output "plan_role_name" {
  description = "Name of the read-only plan-phase role created in every bound account."
  value       = var.plan_role_name
}

output "apply_role_name" {
  description = "Name of the apply-phase role created in every bound account."
  value       = var.apply_role_name
}

output "plan_role_arns" {
  description = "Map of account key -> plan role ARN (set as TFC_AWS_PLAN_ROLE_ARN on the bound workspaces)."
  value       = { for k, b in var.account_bindings : k => "arn:${var.partition}:iam::${b.account_id}:role/${var.plan_role_name}" }
}

output "apply_role_arns" {
  description = "Map of account key -> apply role ARN (set as TFC_AWS_APPLY_ROLE_ARN on the bound workspaces)."
  value       = { for k, b in var.account_bindings : k => "arn:${var.partition}:iam::${b.account_id}:role/${var.apply_role_name}" }
}

output "trust_subjects" {
  description = "Map of account key -> { plan, apply } lists of the exact TFC sub claims each role trusts."
  value       = local.subjects
}

output "sub_condition_operator" {
  description = "IAM condition operator used for the sub claim: StringEquals (exact, default) or StringLike (workspace wildcards enabled)."
  value       = local.sub_operator
}

output "template_body" {
  description = "The rendered CloudFormation template (JSON) deployed by the StackSet."
  value       = local.template_body
}
