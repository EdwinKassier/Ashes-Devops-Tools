output "vpc_id" {
  description = "The ID of the VPC created by the module."
  value       = module.vpc.vpc_id
}

output "subnet_ids_by_tier" {
  description = "Map of subnet tier name to subnet IDs."
  value       = module.vpc.subnet_ids_by_tier
}
