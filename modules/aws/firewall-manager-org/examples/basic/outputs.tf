output "admin_account_id" {
  description = "The account ID registered as the Firewall Manager administrator."
  value       = module.firewall_manager_org.admin_account_id
}

output "policy_ids" {
  description = "Map of FMS policy name to policy ID."
  value       = module.firewall_manager_org.policy_ids
}
