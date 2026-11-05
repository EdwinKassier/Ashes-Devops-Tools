# Host stage (DNS) outputs. Part of modules/gcp/stages/host.

# =============================================================================
# DNS OUTPUTS
# =============================================================================

output "dns_zones" {
  description = "All DNS zone outputs"
  value       = module.dns
}

output "dns_name_servers" {
  description = "Name servers for each public DNS zone"
  value = {
    for k, v in module.dns : k => v.name_servers
  }
}

