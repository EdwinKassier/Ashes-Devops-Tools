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
  description = "ARN of the RAM resource share used to share the regional pools."
  value       = aws_ram_resource_share.this.arn
}

output "regional_pool_cidrs" {
  description = "Map of region to every CIDR provisioned into its regional pool (regional_cidrs plus regional_additional_cidrs)."
  value = {
    for region in var.aws_enabled_regions : region => concat(
      compact([lookup(var.regional_cidrs, region, "")]),
      lookup(var.regional_additional_cidrs, region, []),
    )
  }
}

output "share_principals" {
  description = "RAM principals the regional pools are shared with: the organization ARN, or the entries of share_principal_arns."
  value       = var.share_principal_arns == null ? [var.org_arn] : var.share_principal_arns
}
