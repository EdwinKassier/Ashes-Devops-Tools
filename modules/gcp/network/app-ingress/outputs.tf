output "ip_address" {
  description = "The reserved global anycast IP of the load balancer. Point DNS A records here if dns_managed_zone is not set."
  value       = google_compute_global_address.this.address
}

output "ip_name" {
  description = "Name of the reserved global address resource."
  value       = google_compute_global_address.this.name
}

output "backend_service_id" {
  description = "ID of the backend service, for attaching further Cloud Armor policies or backends."
  value       = google_compute_backend_service.this.id
}

output "certificate_id" {
  description = "ID of the Google-managed SSL certificate. Provisioning completes only after DNS resolves to the load balancer IP."
  value       = google_compute_managed_ssl_certificate.this.id
}

output "https_forwarding_rule_id" {
  description = "ID of the HTTPS (443) global forwarding rule."
  value       = google_compute_global_forwarding_rule.https.id
}

output "managed_domains" {
  description = "Domains the managed certificate covers."
  value       = var.domains
}
