output "project_id" {
  description = "Service project ID created by the workload module"
  value       = module.workload_api_service.project_id
}

output "project_number" {
  description = "Service project number"
  value       = module.workload_api_service.project_number
}
