output "peering_state" {
  description = "Peering state (ACTIVE once both sides are configured)"
  value       = module.vpc_peering.peering_state
}
