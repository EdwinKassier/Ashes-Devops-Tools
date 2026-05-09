output "project_id" {
  description = "Supabase project ID for the QA environment."
  value       = module.qa_environment.project_id
}

output "api_url" {
  description = "Supabase REST API URL for the QA environment."
  value       = module.qa_environment.api_url
}

output "anon_key" {
  description = "Supabase anonymous (public) API key for the QA environment."
  value       = module.qa_environment.anon_key
  sensitive   = true
}
