output "peering_name" {
  description = "VPC peering connection name for the PSA range — required for some service configurations"
  value       = module.psa.peering
}
