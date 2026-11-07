# gcp-projects root: workload + spoke projects.
#
# Extracted from gcp-organization. Reads the org folders and billing
# account, and the admin project / suffix, from the upstream roots via remote
# state. Apply after gcp-organization and before gcp-network-hub.

locals {
  # Remote state when read (count = 1), else the supplied contract. try() only
  # selects the source — it does not unify the two object types — and a failed
  # read still errors at plan time.
  # Each upstream is read through its single `contract` output. A producer
  # state from before that output existed (N-1, not yet re-applied) exposes the
  # same keys as individual outputs, so the read falls back to them; that
  # fallback goes at v1.0 with the individual outputs (UPGRADING.md).
  org       = try(data.terraform_remote_state.gcp_organization[0].outputs.contract, data.terraform_remote_state.gcp_organization[0].outputs, local.organization_contract)
  bootstrap = try(data.terraform_remote_state.gcp_bootstrap[0].outputs.contract, data.terraform_remote_state.gcp_bootstrap[0].outputs, local.bootstrap_contract)

  project_environments = merge(
    {
      shared = {
        display_name = "Shared Services"
        description  = "Shared platform services"
        projects = {
          hub = {
            name            = "hub"
            billing_account = null
            labels = {
              type    = "hub"
              purpose = "network-core"
            }
          }
          dns = {
            name            = "dns"
            billing_account = null
            labels = {
              type    = "dns"
              purpose = "dns-core"
            }
          }
        }
      }
    },
    {
      for env_key, env in local.environments : env_key => {
        display_name = env.display_name
        description  = "${env.display_name} environment"
        projects = {
          host = {
            name            = "host"
            billing_account = null
            labels = merge(
              {
                environment = env_key
                type        = "host"
              },
              env.labels
            )
          }
        }
      }
    }
  )
}

module "projects" {
  source = "../../../modules/gcp/stages/projects"

  project_prefix          = local.project_prefix
  organization_name       = local.organization_name
  default_billing_account = local.org.billing_account
  admin_project_id        = local.bootstrap.admin_project_id
  folders                 = local.org.folders
  environments            = local.project_environments
  project_services        = var.project_services

  # Suffix comes from the gcp-bootstrap root for project-ID consistency.
  suffix = local.bootstrap.suffix

  # Per-environment workload SAs (no org-level roles) get their rights on their
  # OWN env folder here; the network-hub SAs on the shared folder. All come from
  # gcp-bootstrap; try() keeps an older bootstrap state planning (no grants)
  # until gcp-bootstrap is re-applied. The grants are made through the
  # per-folder delegated folderIamAdmin that gcp-organization binds.
  workload_service_accounts = {
    for env, sas in try(local.bootstrap.workload_service_accounts, {}) : env => sas
    if contains(keys(local.environments), env)
  }
  workload_folder_roles    = try(local.bootstrap.workload_folder_roles, { plan = [], apply = [] })
  network_service_accounts = try(local.bootstrap.stage_service_accounts["network-hub"], null)
  network_folder_roles     = try(local.bootstrap.network_folder_roles, { plan = [], apply = [] })
}
