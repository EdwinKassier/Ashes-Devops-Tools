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
