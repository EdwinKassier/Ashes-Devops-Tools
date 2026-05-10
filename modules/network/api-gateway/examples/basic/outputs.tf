output "gateway_hostname" {
  description = "Default hostname for the deployed API gateway"
  value       = module.api_gateway.gateway_default_hostname
}
