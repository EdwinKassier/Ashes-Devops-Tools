output "access_scope_id" {
  description = "ID of the Network Access Analyzer scope, or null when the analyzer is disabled."
  value       = try(aws_ec2_network_insights_access_scope.this[0].id, null)
}
