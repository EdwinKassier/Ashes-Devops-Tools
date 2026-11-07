# Cross-root contract (Convention 4). Consumed by gcp-network-hub (project IDs /
# numbers) and gcp-workload (environment_config). Keep these keys stable.

locals {
  # The gcp-projects cross-root contract: ONE non-sensitive object that downstream
  # roots read as .outputs.contract (tfc-admin: tfe_outputs nonsensitive_values
  # .contract). Never put a sensitive value in it: one sensitive attribute moves
  # the whole object into tfe_outputs' sensitive_values. Keys are stable;
  # scripts/check-contracts.sh enforces the read side.
  contract = {
    projects        = module.projects.projects
    project_ids     = module.projects.project_ids
    project_numbers = module.projects.project_numbers
    environment_config = {
      for env_key, env in local.environments : env_key => {
        folder_id           = try(local.org.folders[env_key].id, null)
        folder_name         = try(local.org.folders[env_key].display_name, null)
        host_project_id     = module.projects.project_ids["${env_key}-host"]
        host_project_number = module.projects.project_numbers["${env_key}-host"]
        region              = env.region
        cidr_block          = env.cidr_block
        labels              = env.labels
        tag_value_ids = {
          environment = try(local.org.tag_values["environment-${env_key}"], null)
        }
        # Explicit production marker for the workload guardrail checks.
        is_production = env.is_production
        # This environment's folder-scoped VPC-SC access policy (gcp-organization);
        # null when scoped policies are disabled or the org state predates them.
        vpc_sc_access_policy_id = try(local.org.scoped_access_policy_ids[env_key], null)
      }
    }
    automation_folder_grants = module.projects.automation_folder_grants
  }
}

output "contract" {
  description = "The gcp-projects cross-root contract: every key below in one non-sensitive object. Downstream roots read this output only; the individual outputs are deprecated aliases kept until v1.0."
  # Exact shape: a key added to local.contract must be added here too, or the
  # conversion drops it silently. scripts/check-contracts.sh compares the
  # top-level keys only: add a NESTED attribute to the type by hand as well.
  type = object({
    projects = map(object({
      id              = string
      project_id      = string
      number          = string
      name            = string
      parent          = string
      labels          = map(string)
      billing_account = string
    }))
    project_ids     = map(string)
    project_numbers = map(string)
    environment_config = map(object({
      folder_id               = string
      folder_name             = string
      host_project_id         = string
      host_project_number     = string
      region                  = string
      cidr_block              = string
      labels                  = map(string)
      tag_value_ids           = object({ environment = string })
      is_production           = bool
      vpc_sc_access_policy_id = string
    }))
    automation_folder_grants = map(object({ folder = string, role = string }))
  })
  value = local.contract
}

output "projects" {
  description = "Deprecated: read contract.projects (removed in v1.0). Map of created projects."
  value       = local.contract.projects
}

output "project_ids" {
  description = "Deprecated: read contract.project_ids (removed in v1.0). Map of project key (e.g. 'shared-hub', '<env>-host') to project ID."
  value       = local.contract.project_ids
}

output "project_numbers" {
  description = "Deprecated: read contract.project_numbers (removed in v1.0). Map of project key to numeric project number."
  value       = local.contract.project_numbers
}

# Stable configuration contract for downstream application environments. Combines
# org folders/tag values (remote state) with this root's project IDs/numbers and
# the environment definitions. gcp-workload reads this.
output "environment_config" {
  description = "Deprecated: read contract.environment_config (removed in v1.0). Per-environment config: folder, host project, region, CIDR, labels, environment tag value, is_production, and the environment's folder-scoped VPC-SC access policy ID."
  value       = local.contract.environment_config
}

output "automation_folder_grants" {
  description = "Deprecated: read contract.automation_folder_grants (removed in v1.0). Folder IAM grants made to the workload / network-hub automation SAs."
  value       = local.contract.automation_folder_grants
}
