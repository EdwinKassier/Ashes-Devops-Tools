output "record_fqdns" {
  description = "Map of record label to the fully qualified domain name Route 53 created."
  value       = module.dns_records.record_fqdns
}
