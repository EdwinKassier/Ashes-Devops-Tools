output "apply_role_arns" {
  description = "Workspace => apply role ARN."
  value       = module.tfc_management_roles.apply_role_arns
}
