# Impersonation is OPTIONAL (audit C2). Leave terraform_admin_email null in
# Terraform Cloud: dynamic credentials already authenticate plan as
# <prefix>-network-hub-plan and apply as <prefix>-network-hub-apply, and a null
# impersonate_service_account means "use the ambient credentials". A plan SA
# cannot impersonate the admin SA, so setting it on a TFC workspace now fails
# closed. Set it only for a deliberate local human run.
provider "google" {
  region                      = var.default_region
  impersonate_service_account = var.terraform_admin_email
}

provider "google-beta" {
  region                      = var.default_region
  impersonate_service_account = var.terraform_admin_email
}

provider "random" {}
