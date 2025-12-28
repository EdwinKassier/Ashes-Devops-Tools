output "admin_project_id" {
  description = "Project ID of the admin project"
  value       = google_project.admin_project.project_id
}

output "admin_project_number" {
  description = "Project Number of the admin project"
  value       = google_project.admin_project.number
}

output "terraform_admin_email" {
  description = "Email of the Terraform Admin Service Account"
  value       = module.terraform_admin_sa.email
}

output "suffix" {
  description = "Random suffix used for uniqueness"
  value       = random_id.suffix.hex
}
