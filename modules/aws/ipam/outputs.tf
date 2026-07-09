output "ipam_id" {
  description = "The ID of the IPAM."
  value       = aws_vpc_ipam.this.id
}

output "top_pool_id" {
  description = "The ID of the top-level IPAM pool that owns the supernet."
  value       = aws_vpc_ipam_pool.top.id
}

output "regional_pool_ids" {
  description = "Map of region to the ID of its regional IPAM pool."
  value       = { for region, pool in aws_vpc_ipam_pool.regional : region => pool.id }
}

output "resource_share_arn" {
  description = "ARN of the RAM resource share used to share the regional pools org-wide."
  value       = aws_ram_resource_share.this.arn
}
