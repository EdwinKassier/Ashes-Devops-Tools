output "service_name" {
  description = "Name of the Cloud Run service."
  value       = module.cloud_run.name
}

output "service_uri" {
  description = "Service URI (reachable only via the internal load balancer)."
  value       = module.cloud_run.uri
}

output "ingress" {
  description = "Effective ingress policy."
  value       = module.cloud_run.ingress
}
