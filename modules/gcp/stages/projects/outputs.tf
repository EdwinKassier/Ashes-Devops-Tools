output "projects" {
  description = "Map of created projects"
  value       = google_project.projects
}

output "project_ids" {
  description = "Map of Project IDs"
  value       = { for k, v in google_project.projects : k => v.project_id }
}

output "project_numbers" {
  description = "Map of Project Numbers"
  value       = { for k, v in google_project.projects : k => v.number }
}

output "automation_folder_grants" {
  description = "Folder IAM grants made to the workload / network-hub automation SAs, keyed \"<env>|<phase>|<role>\" (workload) and \"network|<phase>|<role>\"."
  value = merge(
    { for k, v in local.workload_folder_grants : k => { folder = v.folder, role = v.role } },
    { for k, v in local.network_folder_grants : "network|${k}" => { folder = v.folder, role = v.role } },
  )
}
