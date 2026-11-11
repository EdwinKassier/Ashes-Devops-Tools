/**
 * Copyright 2026 Ashes
 *
 * Secure Web Proxy Module - Outputs
 */

output "gateway_id" {
  description = "ID of the Secure Web Proxy gateway (projects/<project>/locations/<region>/gateways/<name>)."
  value       = google_network_services_gateway.this.id
}

output "gateway_address" {
  description = "Internal address clients (or next-hop routes) send traffic to: var.address when set, else the address Google allocated (known after apply)."
  value       = var.address != null ? var.address : try(google_network_services_gateway.this.addresses[0], null)
}

output "gateway_ports" {
  description = "Ports the gateway listens on."
  value       = var.ports
}

output "gateway_security_policy_id" {
  description = "ID of the gateway security policy."
  value       = google_network_security_gateway_security_policy.this.id
}

output "url_list_id" {
  description = "ID of the FQDN allowlist URL list, or null when allowed_fqdns is empty."
  value       = try(google_network_security_url_lists.allowlist[0].id, null)
}

output "proxy_only_subnet_id" {
  description = "ID of the proxy-only subnet this module created, or null when create_proxy_only_subnet is false."
  value       = try(google_compute_subnetwork.proxy_only[0].id, null)
}

output "service_attachment_id" {
  description = "ID of the PSC service attachment (projects/<project>/regions/<region>/serviceAttachments/<name>) consumers target from their endpoint, or null when create_service_attachment is false."
  value       = try(google_compute_service_attachment.this[0].id, null)
}
