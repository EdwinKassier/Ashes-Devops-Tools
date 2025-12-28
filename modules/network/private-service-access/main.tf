/**
 * Copyright 2023 Ashes
 *
 * Private Service Access Module - Main Configuration
 * 
 * Reserves a Global Internal IP range and peers it with Google Service Networking
 * for access to managed services like Cloud SQL, Memorystore, etc.
 */

# Reserve Global Internal IP Range
resource "google_compute_global_address" "private_ip_alloc" {
  project       = var.project_id
  name          = var.name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.prefix_length
  network       = var.vpc_network
  address       = var.address
  ip_version    = var.ip_version
  labels        = var.labels
}

# Create Private Connection to Google Service Networking
resource "google_service_networking_connection" "private_service_access" {
  network                 = var.vpc_network
  service                 = var.service
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
}
