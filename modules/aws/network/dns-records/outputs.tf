output "record_fqdns" {
  description = "Map of record key to the created record's fully qualified domain name."
  value       = { for k, r in aws_route53_record.this : k => r.fqdn }
}

output "record_names" {
  description = "Map of record key to the created record name."
  value       = { for k, r in aws_route53_record.this : k => r.name }
}
