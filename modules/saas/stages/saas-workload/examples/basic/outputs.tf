output "supabase_project_id" {
  description = "Supabase project ID for the QA environment."
  value       = module.qa_saas_workload.supabase_project_id
}

output "supabase_api_url" {
  description = "Supabase REST API URL for the QA environment."
  value       = module.qa_saas_workload.supabase_api_url
}

output "vercel_project_id" {
  description = "Vercel project ID for the QA environment."
  value       = module.qa_saas_workload.vercel_project_id
}
