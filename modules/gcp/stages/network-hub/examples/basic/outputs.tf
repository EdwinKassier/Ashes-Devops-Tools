output "hub_vpc_self_link" {
  description = "Self-link of the hub VPC — pass this to spoke projects for peering"
  value       = module.network_hub.hub_vpc_self_link
}
