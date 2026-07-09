output "alarm_names" {
  description = "Names of the AWS/Usage CloudWatch alarms."
  value       = module.service_quotas.alarm_names
}
