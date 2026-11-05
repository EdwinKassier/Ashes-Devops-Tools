output "firewall_arn" {
  description = "ARN of the Network Firewall, or null when the firewall is disabled."
  value       = try(aws_networkfirewall_firewall.this[0].arn, null)
}

output "firewall_endpoint_ids" {
  description = "VPC endpoint IDs from the firewall's per-AZ sync states, or the firewall ID as a fallback (sync-state endpoint IDs are provider-computed and may be unknown at plan time). Null when disabled."
  value = try(
    flatten([
      for ss in aws_networkfirewall_firewall.this[0].firewall_status[0].sync_states :
      [for att in ss.attachment : att.endpoint_id]
    ]),
    try(aws_networkfirewall_firewall.this[0].id, null)
  )
}

output "firewall_endpoint_ids_by_az" {
  description = "Map of availability zone -> Network Firewall VPC endpoint ID, from the firewall's per-AZ sync states. Used to route each AZ's inspection traffic to the SAME-AZ endpoint (symmetric routing with TGW appliance mode). Empty when disabled; values are provider-computed (known after apply)."
  value = try({
    for ss in aws_networkfirewall_firewall.this[0].firewall_status[0].sync_states :
    ss.availability_zone => ss.attachment[0].endpoint_id
  }, {})
}

output "stateful_rule_group_references" {
  description = "Ordered list of { arn, priority } stateful rule group references in the STRICT_ORDER policy (managed threat groups, then custom rules, then the egress allowlist)."
  value       = var.enable_network_firewall ? local.stateful_references : []
}
