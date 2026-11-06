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

output "route_table_ids_by_tier" {
  description = "Map of subnet tier name to the list of route table IDs for that tier (one per AZ). Element order matches subnet_ids_by_tier, so index i of both lists is the same AZ."
  # Iterate subnet_defs exactly as subnet_ids_by_tier does so the two lists stay
  # index-aligned even when availability_zones is not sorted.
  value = {
    for tier in keys(var.subnets) : tier => [
      for key, def in local.subnet_defs : aws_route_table.this["${def.tier}-${def.index}"].id if def.tier == tier
    ]
  }
}

output "internet_gateway_id" {
  description = "ID of the internet gateway, or null when create_internet_gateway is false."
  value       = try(aws_internet_gateway.this[0].id, null)
}

output "gateway_endpoint_ids" {
  description = "Map of gateway endpoint service name (e.g. s3, dynamodb) to its VPC endpoint ID."
  value       = { for svc, ep in aws_vpc_endpoint.gateway : svc => ep.id }
}
