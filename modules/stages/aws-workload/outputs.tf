output "vpc_id" {
  description = "The ID of the workload spoke VPC."
  value       = module.vpc.vpc_id
}

output "subnet_ids_by_tier" {
  description = "Map of subnet tier name to the list of subnet IDs created for that tier (one per AZ) in the spoke VPC."
  value       = module.vpc.subnet_ids_by_tier
}

output "tgw_attachment_id" {
  description = "The ID of the spoke VPC's transit-gateway attachment to the shared hub."
  value       = aws_ec2_transit_gateway_vpc_attachment.spoke.id
}

output "workload_role_arns" {
  description = "Map of workload IAM role name to role ARN."
  value       = module.iam_role.role_arns
}
