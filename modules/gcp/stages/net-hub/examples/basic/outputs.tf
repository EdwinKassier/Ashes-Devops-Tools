output "network_self_link" {
  description = "Self-link of the hub VPC network (spokes peer to it)"
  value       = module.example.network_self_link
}

output "nat_ip" {
  description = "Hub Cloud NAT IP addresses"
  value       = module.example.nat_ip
}
