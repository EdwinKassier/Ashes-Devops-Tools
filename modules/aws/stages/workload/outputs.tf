output "vpc_id" {
  description = "The ID of the workload spoke VPC."
  value       = module.vpc.vpc_id
}

output "subnet_ids_by_tier" {
  description = "Map of subnet tier name to the list of subnet IDs created for that tier (one per AZ) in the spoke VPC."
  value       = module.vpc.subnet_ids_by_tier
}

output "tgw_attachment_id" {
  description = "The ID of the spoke VPC's transit-gateway attachment to the shared hub (null in standalone mode, tgw_id = null)."
  value       = try(aws_ec2_transit_gateway_vpc_attachment.spoke[0].id, null)
}

output "workload_role_arns" {
  description = "Map of workload IAM role name to role ARN."
  value       = module.iam_role.role_arns
}

output "route_table_ids_by_tier" {
  description = "Map of spoke subnet tier to its per-AZ route table IDs (owned by the vpc module)."
  value       = module.vpc.route_table_ids_by_tier
}

output "tgw_routes" {
  description = "The spoke routing contract handed to the vpc module: tier -> list of {destination_cidr_block, transit_gateway_id} routes to the shared transit gateway."
  value       = local.spoke_routes
}

output "name" {
  description = "The resolved spoke name (var.name, else workload-<environment>)."
  value       = local.name
}

output "config_role_arn" {
  description = "IAM role the workload account's Config recorders use (the AWSServiceRoleForConfig service-linked role unless config_role_arn was set)."
  value       = module.config_recorder.config_role_arn
}

output "internet_gateway_id" {
  description = "ID of the spoke's internet gateway, or null when neither enable_public_subnets nor create_internet_gateway is set."
  value       = module.vpc.internet_gateway_id
}
