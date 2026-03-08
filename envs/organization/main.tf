locals {
  shared_environment = {
    display_name            = "Shared Services"
    description             = "Shared platform services"
    iam_group_role_bindings = var.shared_iam_group_role_bindings
  }

  organization_units = merge(
    {
      shared = local.shared_environment
    },
    {
      for env_key, env in var.environments : env_key => {
        display_name            = env.display_name
        description             = "${env.display_name} environment"
        iam_group_role_bindings = env.iam_group_role_bindings
      }
    }
  )

  project_environments = merge(
    {
      shared = {
        display_name = local.shared_environment.display_name
        description  = local.shared_environment.description
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

  tfc_workspaces = concat(
    ["organization"],
    [for env_key in sort(keys(var.environments)) : "apps-${env_key}"]
  )
}

# 1. Bootstrap: Automation Foundation
module "bootstrap" {
  source = "../../modules/stages/bootstrap"

  project_prefix   = var.project_prefix
  org_id           = data.google_organization.org.org_id
  billing_account  = data.google_billing_account.billing.id
  admin_email      = var.admin_email
  github_org       = var.github_org
  github_repo      = var.github_repo
  tfc_organization = var.tfc_organization
  tfc_workspaces   = local.tfc_workspaces
}

# 2. Organization: Hierarchy & Governance
module "organization" {
  source = "../../modules/stages/organization"

  domain               = var.domain
  org_id               = data.google_organization.org.org_id
  customer_id          = data.google_organization.org.directory_customer_id
  admin_project_id     = module.bootstrap.admin_project_id
  admin_project_number = module.bootstrap.admin_project_number
  billing_account      = data.google_billing_account.billing.id
  project_prefix       = var.project_prefix
  environments         = local.organization_units

  admin_email               = var.admin_email
  break_glass_user          = var.break_glass_user
  terraform_admin_email     = module.bootstrap.terraform_admin_email
  organization_admin_groups = var.organization_admin_groups
  billing_admin_groups      = var.billing_admin_groups

  default_region                        = var.default_region
  allowed_regions                       = var.allowed_regions
  strict_folder_policy_environment_keys = var.strict_folder_policy_environment_keys
  security_contact_email                = var.security_contact_email
  billing_contact_email                 = var.billing_contact_email
  monthly_budget_amount                 = var.monthly_budget_amount
  budget_currency                       = var.budget_currency

  depends_on = [module.bootstrap]
}

# 3. Projects: Workload & Spoke Projects
module "projects" {
  source = "../../modules/stages/projects"

  project_prefix          = var.project_prefix
  organization_name       = var.organization_name
  default_billing_account = data.google_billing_account.billing.id
  admin_project_id        = module.bootstrap.admin_project_id
  folders                 = module.organization.folders
  environments            = local.project_environments
  project_services        = var.project_services

  # Pass the suffix from bootstrap to ensure ID consistency
  suffix = module.bootstrap.suffix

  depends_on = [module.organization]
}

# 4. Network Hub: Connectivity Layer
module "network_hub" {
  source = "../../modules/stages/network-hub"

  project_prefix = var.project_prefix
  default_region = var.default_region

  hub_project_id = module.projects.project_ids["shared-hub"]
  dns_project_id = module.projects.project_ids["shared-dns"]
  spoke_project_ids = {
    for env_key in sort(keys(var.environments)) :
    env_key => module.projects.project_ids["${env_key}-host"]
  }

  org_id  = data.google_organization.org.org_id
  folders = module.organization.folders

  depends_on = [module.projects]
}
