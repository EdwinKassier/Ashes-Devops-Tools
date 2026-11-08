output "ip_address" {
  description = "Reserved global anycast IP of the load balancer."
  value       = module.ingress.ip_address
}

output "certificate_id" {
  description = "Google-managed certificate ID."
  value       = module.ingress.certificate_id
}

output "managed_domains" {
  description = "Domains the managed certificate covers."
  value       = module.ingress.managed_domains
}
