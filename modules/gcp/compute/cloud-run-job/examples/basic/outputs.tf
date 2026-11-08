output "job_name" {
  description = "Name of the Cloud Run job."
  value       = module.cloud_run_job.name
}

output "job_id" {
  description = "Fully qualified Cloud Run job ID."
  value       = module.cloud_run_job.id
}
