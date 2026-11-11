output "projects" {
  description = "Map of created projects, keyed \"<env>-<project>\": { id, project_id, number, name, parent, labels, billing_account }."
  value = {
    for k, p in module.project : k => {
      id              = p.id
      project_id      = p.project_id
      number          = p.number
      name            = p.name
      parent          = p.parent
      labels          = p.labels
      billing_account = p.billing_account
    }
  }
}

output "project_ids" {
  description = "Map of Project IDs"
  value       = { for k, v in module.project : k => v.project_id }
}

output "project_numbers" {
  description = "Map of Project Numbers"
  value       = { for k, v in module.project : k => v.number }
}

output "automation_folder_grants" {
  description = "Folder IAM grants made to the workload / network-hub automation SAs, keyed \"<env>|<phase>|<role>\" (workload), \"network|<phase>|<role>\" (network-hub on the shared folder) and \"network-env|<env>|<phase>\" (network-hub compute.viewer on each environment folder)."
  value = merge(
    { for k, v in local.workload_folder_grants : k => { folder = v.folder, role = v.role } },
    { for k, v in local.network_folder_grants : "network|${k}" => { folder = v.folder, role = v.role } },
    { for k, v in local.network_env_viewer_grants : "network-env|${k}" => { folder = v.folder, role = "roles/compute.viewer" } },
  )
}
