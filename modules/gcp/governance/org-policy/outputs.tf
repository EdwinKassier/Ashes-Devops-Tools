# -----------------------------------------------------------------------------
# Policy Outputs
# -----------------------------------------------------------------------------

output "boolean_policy_names" {
  description = "Map of boolean policy constraint names to their full resource names"
  value       = { for k, v in google_org_policy_policy.boolean_policies : k => v.name }
}

output "list_policy_names" {
  description = "Map of list policy constraint names to their full resource names"
  value       = { for k, v in google_org_policy_policy.list_policies : k => v.name }
}

output "enforced_boolean_policies" {
  description = "List of boolean policies that are enforced (enforce = true)"
  value       = [for p in var.boolean_policies : p.constraint if p.enforce]
}

output "disabled_boolean_policies" {
  description = "List of boolean policies that are disabled (enforce = false)"
  value       = [for p in var.boolean_policies : p.constraint if !p.enforce]
}

output "parent" {
  description = "The parent resource where policies are applied"
  value       = var.parent
}

output "custom_constraints" {
  description = "Map of created custom constraints"
  value       = { for k, v in google_org_policy_custom_constraint.custom_constraints : k => v.name }
}

# -----------------------------------------------------------------------------
# Preset Policy Pack Outputs
# Reference these in your module call to apply a recommended baseline.
# Example:
#   boolean_policies = module.org_policy.preset_security_hardening
# -----------------------------------------------------------------------------

output "preset_security_hardening" {
  description = "Recommended security hardening boolean policy pack (SQL public IP, uniform bucket access, Shielded VM, OS Login, serial port, service account key creation)"
  value       = local.preset_security_hardening_boolean
}

output "preset_cmek_required" {
  description = "CMEK-required list policy pack — denies storage/BQ/Spanner/Pub/Sub/Secret Manager resources created without customer-managed encryption keys"
  value       = local.preset_cmek_required_list
}

output "preset_us_eu_locations" {
  description = "Regional restriction list policy pack — limits resource creation to US and EU regions"
  value       = local.preset_us_eu_locations_list
}

output "preset_compute_security" {
  description = "Strict compute security boolean policy pack (Shielded VM, serial port, nested virtualisation, OS Login, guest attributes)"
  value       = local.preset_compute_security_boolean
}

output "preset_no_external_ips" {
  description = "Zero-trust network list policy pack — denies all external IP addresses on compute instances"
  value       = local.preset_no_external_ips_list
}
