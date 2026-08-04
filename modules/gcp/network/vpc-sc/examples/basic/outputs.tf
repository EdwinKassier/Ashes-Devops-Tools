output "perimeter_name" {
  description = "The resource name of the service perimeter"
  value       = module.data_perimeter.name
}

output "access_policy_name" {
  description = "The access policy under which the perimeter was created"
  value       = module.data_perimeter.access_policy_name
}
