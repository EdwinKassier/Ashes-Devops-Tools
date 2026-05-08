output "nat_ip_addresses" {
  description = "The auto-allocated external IP addresses for outbound traffic"
  value       = module.nat.nat_ips
}
