output "api_id" {
  description = "ID of the HTTP API."
  value       = module.api_gateway.api_id
}

output "api_endpoint" {
  description = "Default endpoint URL of the HTTP API."
  value       = module.api_gateway.api_endpoint
}

output "stage_invoke_url" {
  description = "Invoke URL of the deployed stage."
  value       = module.api_gateway.stage_invoke_url
}
