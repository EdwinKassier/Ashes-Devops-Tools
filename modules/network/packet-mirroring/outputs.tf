/**
 * Copyright 2023 Ashes
 *
 * Packet Mirroring Module - Outputs
 */

# Standard interface outputs
output "id" {
  description = "The ID of the packet mirroring policy"
  value       = google_compute_packet_mirroring.mirroring.id
}

output "name" {
  description = "The name of the packet mirroring policy"
  value       = google_compute_packet_mirroring.mirroring.name
}

output "policy" {
  description = "The full packet mirroring policy resource"
  value       = google_compute_packet_mirroring.mirroring
}

output "collector_ilb" {
  description = "The collector ILB URL"
  value       = var.collector_ilb_url
}

output "region" {
  description = "The region of the packet mirroring policy"
  value       = google_compute_packet_mirroring.mirroring.region
}
