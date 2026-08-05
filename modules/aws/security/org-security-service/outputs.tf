output "enabled_services" {
  description = "The set of org-security services enabled by this module (echo of the input)."
  value       = var.enabled_services
}

output "macie_account_id" {
  description = "The Macie account ID in the Security Tooling account, or null when Macie is not enabled."
  value       = try(aws_macie2_account.this[0].id, null)
}

output "detective_graph_arn" {
  description = "The Detective behavior graph ARN, or null when Detective is not enabled."
  value       = try(aws_detective_graph.this[0].graph_arn, null)
}

output "resource_explorer_index_arn" {
  description = "The Resource Explorer aggregator index ARN, or null when Resource Explorer is not enabled."
  value       = try(aws_resourceexplorer2_index.this[0].arn, null)
}
