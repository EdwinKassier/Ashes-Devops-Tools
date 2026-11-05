# Impersonation is OPTIONAL (audit C2): leave terraform_admin_email null in TFC —
# dynamic credentials already run plan as <prefix>-projects-plan and apply as
# <prefix>-projects-apply. Set it only for a deliberate local human run.
provider "google" {
  region                      = var.default_region
  impersonate_service_account = var.terraform_admin_email
}

provider "google-beta" {
  region                      = var.default_region
  impersonate_service_account = var.terraform_admin_email
}

provider "random" {}
