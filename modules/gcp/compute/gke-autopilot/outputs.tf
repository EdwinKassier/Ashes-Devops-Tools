/**
 * Copyright 2023 Ashes
 *
 * GKE Autopilot Module - Outputs
 */

output "name" {
  description = "The name of the GKE Autopilot cluster"
  value       = google_container_cluster.this.name
}

output "endpoint" {
  description = "The IP address of the cluster's Kubernetes control-plane endpoint"
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "ca_certificate" {
  description = "Base64-encoded public certificate of the cluster's certificate authority"
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_pool" {
  description = "The Workload Identity pool (<project>.svc.id.goog) bound to the cluster"
  value       = local.workload_pool
}
