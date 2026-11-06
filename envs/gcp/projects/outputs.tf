# Cross-root contract (Convention 4). Consumed by gcp-network-hub (project IDs /
# numbers) and gcp-workload (environment_config). Keep these keys stable.

output "projects" {
  description = "Map of created projects."
  value       = module.projects.projects
}

output "project_ids" {
  description = "Map of project key (e.g. 'shared-hub', '<env>-host') to project ID."
  value       = module.projects.project_ids
}

output "project_numbers" {
  description = "Map of project key to numeric project number."
  value       = module.projects.project_numbers
}

# Stable configuration contract for downstream application environments. Combines
# org folders/tag values (remote state) with this root's project IDs/numbers and
# the environment definitions. gcp-workload reads this.
output "environment_config" {
  description = "Per-environment config: folder, host project, region, CIDR, labels, environment tag value, is_production, and the environment's folder-scoped VPC-SC access policy ID."
  value = {
    for env_key, env in var.environments : env_key => {
      folder_id           = local.org.folders[env_key].id
      folder_name         = local.org.folders[env_key].display_name
      host_project_id     = module.projects.project_ids["${env_key}-host"]
      host_project_number = module.projects.project_numbers["${env_key}-host"]
      region              = env.region
      cidr_block          = env.cidr_block
      labels              = env.labels
      tag_value_ids = {
        environment = local.org.tag_values["environment-${env_key}"]
      }
      # Explicit production marker for the workload guardrail checks.
      is_production = env.is_production
      # This environment's folder-scoped VPC-SC access policy (gcp-organization);
      # null when scoped policies are disabled or the org state predates them.
      vpc_sc_access_policy_id = try(local.org.scoped_access_policy_ids[env_key], null)
    }
  }
}

output "automation_folder_grants" {
  description = "Folder IAM grants made to the workload / network-hub automation SAs."
  value       = module.projects.automation_folder_grants
}
