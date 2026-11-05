output "plan_role_arns" {
  description = "Account key -> plan role ARN (TFC_AWS_PLAN_ROLE_ARN)."
  value       = module.tfc_oidc_baseline.plan_role_arns
}

output "apply_role_arns" {
  description = "Account key -> apply role ARN (TFC_AWS_APPLY_ROLE_ARN)."
  value       = module.tfc_oidc_baseline.apply_role_arns
}
