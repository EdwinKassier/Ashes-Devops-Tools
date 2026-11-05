# Host stage (firewall) outputs. Part of modules/gcp/stages/host.

# =============================================================================
# ADDITIONAL FIREWALL RULES OUTPUTS
# =============================================================================

output "additional_firewall_rules" {
  description = "All additional firewall rule outputs"
  value       = module.additional_firewall_rules
}

output "additional_firewall_rule_ids" {
  description = "The IDs of all additional firewall rules"
  value = {
    for k, v in module.additional_firewall_rules : k => v.id
  }
}

# =============================================================================
# HIERARCHICAL FIREWALL POLICY OUTPUTS
# =============================================================================

output "hierarchical_firewall_policies" {
  description = "All hierarchical firewall policy outputs"
  value       = module.hierarchical_firewall_policies
}

output "hierarchical_firewall_policy_ids" {
  description = "The IDs of all hierarchical firewall policies"
  value = {
    for k, v in module.hierarchical_firewall_policies : k => v.id
  }
}

