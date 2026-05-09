output "vercel_project_id" {
  description = "Vercel project ID."
  value       = module.vercel_project.project_id
}

output "vercel_project_name" {
  description = "Vercel project name."
  value       = module.vercel_project.project_name
}

output "uat_environment_id" {
  description = "Vercel UAT custom environment ID."
  value       = module.vercel_project.uat_environment_id
}
