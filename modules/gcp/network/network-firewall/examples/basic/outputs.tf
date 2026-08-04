output "health_check_rule_id" {
  description = "Firewall rule ID that allows GCP health check probe traffic"
  value       = module.allow_health_checks.firewall_rule_id
}
