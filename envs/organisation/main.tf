# Modular Monolith Root Configuration
# Composes the stage modules to enforce order and data passing.

# 1. Bootstrap: Automation Foundation
module "bootstrap" {
  source = "../../modules/stages/bootstrap"

  project_prefix  = var.project_prefix
  org_id          = data.google_organization.org.org_id
  billing_account = data.google_billing_account.billing.id
  admin_email     = var.admin_email
  github_org      = var.github_org
  github_repo     = var.github_repo
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
  environments         = var.environments

  admin_email               = var.admin_email
  break_glass_user          = var.break_glass_user
  terraform_admin_email     = module.bootstrap.terraform_admin_email
  developers_group_email    = var.developers_group_email
  organization_admin_groups = var.organization_admin_groups
  billing_admin_groups      = var.billing_admin_groups

  default_region         = var.default_region
  allowed_regions        = var.allowed_regions
  security_contact_email = var.security_contact_email
  billing_contact_email  = var.billing_contact_email
  monthly_budget_amount  = var.monthly_budget_amount
  budget_currency        = var.budget_currency

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
  environments            = var.environments
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
    "dev"  = module.projects.project_ids["dev-host"]
    "prod" = module.projects.project_ids["prod-host"]
    "uat"  = module.projects.project_ids["uat-host"]
  }

  org_id  = data.google_organization.org.org_id
  folders = module.organization.folders

  depends_on = [module.projects]
}
