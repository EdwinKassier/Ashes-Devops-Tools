# Host stage (edge and ingress) outputs. Part of modules/gcp/stages/host.

# =============================================================================
# CLOUD ARMOR OUTPUTS
# =============================================================================

output "cloud_armor" {
  description = "The Cloud Armor security policy (if enabled)"
  value       = var.enable_cloud_armor ? module.cloud_armor[0] : null
}

output "security_policy_id" {
  description = "The Cloud Armor security policy ID"
  value       = var.enable_cloud_armor ? module.cloud_armor[0].policy_id : null
}

output "security_policy_self_link" {
  description = "The Cloud Armor security policy self link"
  value       = var.enable_cloud_armor ? module.cloud_armor[0].policy_self_link : null
}

# =============================================================================
# CDN OUTPUTS
# =============================================================================

output "cdn" {
  description = "The CDN module outputs (if enabled)"
  value       = var.enable_cdn ? module.cdn[0] : null
}

output "cdn_ip" {
  description = "The global load balancer IP address"
  value       = var.enable_cdn ? module.cdn[0].load_balancer_ip : null
}

output "cdn_backend_service_id" {
  description = "The CDN backend service ID"
  value       = var.enable_cdn ? module.cdn[0].backend_service_id : null
}

# =============================================================================
# API GATEWAY OUTPUTS
# =============================================================================

output "api_gateway" {
  description = "The API Gateway module outputs (if enabled)"
  value       = var.enable_api_gateway ? module.api_gateway[0] : null
}

output "api_gateway_hostname" {
  description = "The default hostname of the API Gateway"
  value       = var.enable_api_gateway ? module.api_gateway[0].gateway_default_hostname : null
}

output "api_gateway_neg_id" {
  description = "The serverless NEG ID for load balancer integration"
  value       = var.enable_api_gateway ? module.api_gateway[0].serverless_neg_id : null
}

# =============================================================================
# INTERNAL LOAD BALANCER OUTPUTS
# =============================================================================

output "internal_load_balancers" {
  description = "All internal load balancer outputs"
  value       = module.internal_load_balancers
}

output "internal_load_balancer_ips" {
  description = "The IP addresses of all internal load balancers"
  value = {
    for k, v in module.internal_load_balancers : k => v.ip_address
  }
}

output "internal_load_balancer_backend_services" {
  description = "The backend service self_links for all internal load balancers"
  value = {
    for k, v in module.internal_load_balancers : k => v.backend_service_self_link
  }
}

