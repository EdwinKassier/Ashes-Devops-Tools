# gcp-projects root: workload + spoke projects.
#
# Extracted from gcp-organization (audit H3). Reads the org folders and billing
# account, and the admin project / suffix, from the upstream roots via remote
# state. Apply after gcp-organization and before gcp-network-hub.

locals {
  org       = data.terraform_remote_state.gcp_organization.outputs
  bootstrap = data.terraform_remote_state.gcp_bootstrap.outputs

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
      for env_key, env in var.environments : env_key => {
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

  project_prefix          = var.project_prefix
  organization_name       = var.organization_name
  default_billing_account = local.org.billing_account
  admin_project_id        = local.bootstrap.admin_project_id
  folders                 = local.org.folders
  environments            = local.project_environments
  project_services        = var.project_services

  # Suffix comes from the gcp-bootstrap root for project-ID consistency.
  suffix = local.bootstrap.suffix
}
