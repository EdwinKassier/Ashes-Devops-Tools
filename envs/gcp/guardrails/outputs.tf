# Containment defaults ON for a production estate; the derived settings are
# validated here (a variable validation cannot read the derived locals without
# a cycle). A failed precondition fails the plan.
output "admin_containment_enabled" {
  description = "Whether the admin-containment deny policy is on (explicit enable_admin_containment, else gcp.admin_containment, else on when any environment is_production or a break-glass principal is set)."
  value       = local.enable_admin_containment

  precondition {
    condition     = !local.enable_admin_containment || length(local.containment_exempt_principals) > 0
    error_message = "Admin containment is on (it defaults on when an environment is_production) but no break-glass principal is set, so the deny would lock out everyone. Set gcp.break_glass_group in config/landing-zone.yaml (or containment_exempt_principals), or set gcp.admin_containment: false explicitly to run production without it."
  }

  precondition {
    condition     = !anytrue([for p in local.containment_exempt_principals : can(regex("(?i)(replace-me|your-domain|example\\.(com|org|net)|\\.invalid$|changeme)", p))])
    error_message = "The break-glass principal (gcp.break_glass_group / containment_exempt_principals) is still a placeholder. Set your real break-glass group."
  }
}

output "deny_policy_names" {
  description = "Names of the IAM deny policies applied at the org node."
  value       = module.guardrails.deny_policy_names
}

output "deny_policy_ids" {
  description = "Map of deny-policy name to resource ID."
  value       = module.guardrails.deny_policy_ids
}

output "admin_containment_rules" {
  description = "Rules of the admin-containment deny policy (empty when containment is off)."
  value       = module.guardrails.admin_containment_rules
}

output "deny_policy_specs" {
  description = "Map of deny-policy ID => gcloud policy-file JSON, for the break-glass path only (docs/runbooks/break-glass.md). Routine changes go through a security-team apply of this workspace."
  value       = module.guardrails.deny_policy_specs
}
