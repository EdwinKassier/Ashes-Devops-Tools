output "ca_pool_id" {
  description = "Fully qualified ID of the CA pool (projects/<project>/locations/<location>/caPools/<name>)."
  value       = google_privateca_ca_pool.this.id
}

output "ca_pool_name" {
  description = "Name of the CA pool."
  value       = google_privateca_ca_pool.this.name
}

output "certificate_authority_id" {
  description = "Fully qualified ID of the certificate authority, or null when enable_ca is false."
  value       = try(google_privateca_certificate_authority.this[0].id, null)
}

output "ca_state" {
  description = "Current state of the certificate authority (e.g. ENABLED, STAGED), or null when enable_ca is false."
  value       = try(google_privateca_certificate_authority.this[0].state, null)
}
