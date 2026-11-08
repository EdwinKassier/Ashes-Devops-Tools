output "cluster_name" {
  description = "Name of the Autopilot cluster."
  value       = module.gke.name
}

output "endpoint" {
  description = "Private control-plane endpoint."
  value       = module.gke.endpoint
  sensitive   = true
}

output "workload_pool" {
  description = "Workload Identity pool for Kubernetes service accounts."
  value       = module.gke.workload_pool
}
