output "record_fqdns" {
  description = "Map of record key to the created record's fully qualified name."
  value       = { for k, r in google_dns_record_set.this : k => r.name }
}

output "record_ids" {
  description = "Map of record key to the created record set ID."
  value       = { for k, r in google_dns_record_set.this : k => r.id }
}
