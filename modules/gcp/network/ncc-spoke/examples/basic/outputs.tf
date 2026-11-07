output "spoke_id" {
  description = "The NCC spoke ID"
  value       = module.ncc_spoke.id
}

output "producer_spoke_ids" {
  description = "The producer VPC spoke IDs"
  value       = module.ncc_spoke.producer_spoke_ids
}
