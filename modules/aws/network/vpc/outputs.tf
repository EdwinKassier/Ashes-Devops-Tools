output "vpc_id" {
  description = "The ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "The IPv4 CIDR used for the VPC and subnet math."
  value       = local.vpc_cidr
}

output "subnet_ids_by_tier" {
  description = "Map of subnet tier name to the list of subnet IDs created for that tier (one per AZ)."
  # Group by the tier recorded in local.subnet_defs (known at plan time) rather
  # than by a provider-computed tag, so the grouping is deterministic.
  value = {
    for tier in keys(var.subnets) : tier => [
      for key, def in local.subnet_defs : aws_subnet.this[key].id if def.tier == tier
    ]
  }
}
