/**
 * Copyright 2023 Ashes
 *
 * API Gateway Module - Outputs
 */

output "api" {
  description = "The created API Gateway API resource"
  value       = google_api_gateway_api.api
}

output "api_config" {
  description = "The created API Gateway config resource"
  value       = google_api_gateway_api_config.api_config
}

output "gateway" {
  description = "The created API Gateway instance"
  value       = google_api_gateway_gateway.gateway
}

output "id" {
  description = "The ID of the API Gateway"
  value       = google_api_gateway_gateway.gateway.id
}

output "self_link" {
  description = "The URI of the API Gateway"
  value       = google_api_gateway_gateway.gateway.id
}

output "gateway_default_hostname" {
  description = "The default hostname of the API Gateway"
  value       = google_api_gateway_gateway.gateway.default_hostname
}

output "service_name" {
  description = "The full service name used for the API Gateway"
  value       = google_api_gateway_api.api.managed_service
}

output "serverless_neg_id" {
  description = "The ID of the Serverless NEG for Load Balancer integration"
  value       = google_compute_region_network_endpoint_group.serverless_neg.id
} 