output "endpoint_ids" {
  description = "Map of interface service name to VPC endpoint ID."
  value       = module.vpc_endpoints.endpoint_ids
}

output "phz_id" {
  description = "Zone ID of the shared private hosted zone."
  value       = module.vpc_endpoints.phz_id
}
