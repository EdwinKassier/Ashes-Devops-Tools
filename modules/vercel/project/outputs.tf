output "project_id" {
  description = "The Vercel project ID (prj_xxx format)."
  value       = vercel_project.this.id
}

output "project_name" {
  description = "The Vercel project name."
  value       = vercel_project.this.name
}

output "uat_environment_id" {
  description = "The Vercel custom environment ID for the UAT environment. Pass to vercel_project_domain or additional env var resources targeting UAT."
  value       = vercel_custom_environment.uat.id
}
