output "pairing_key" {
  description = "Share this key with your service provider to activate the interconnect"
  value       = module.partner_interconnect.attachment
  sensitive   = true
}
