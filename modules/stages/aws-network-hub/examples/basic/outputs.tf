output "tgw_id" {
  description = "The ID of the transit gateway."
  value       = module.aws_network_hub.tgw_id
}

output "ipam_pool_ids" {
  description = "Map of region to the ID of its regional IPAM pool."
  value       = module.aws_network_hub.ipam_pool_ids
}

output "inspection_vpc_id" {
  description = "The ID of the inspection VPC."
  value       = module.aws_network_hub.inspection_vpc_id
}

output "egress_vpc_id" {
  description = "The ID of the centralized egress VPC."
  value       = module.aws_network_hub.egress_vpc_id
}
