/**
 * Copyright 2023 Ashes
 *
 * Packet Mirroring Module - Outputs
 */

# Standard interface outputs
output "id" {
  description = "The ID of the packet mirroring policy, or null when enable = false"
  value       = var.enable ? google_compute_packet_mirroring.mirroring[0].id : null
}

output "name" {
  description = "The name of the packet mirroring policy, or null when enable = false"
  value       = var.enable ? google_compute_packet_mirroring.mirroring[0].name : null
}

output "policy" {
  description = "The full packet mirroring policy resource object, or null when enable = false"
  value       = var.enable ? google_compute_packet_mirroring.mirroring[0] : null
}

output "collector_ilb" {
  description = "The collector ILB URL"
  value       = var.collector_ilb_url
}

output "region" {
  description = "The region of the packet mirroring policy"
  value       = var.region
}
