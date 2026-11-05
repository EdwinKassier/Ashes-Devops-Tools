# Impersonation is OPTIONAL (audit C2). In Terraform Cloud leave
# terraform_admin_email unset: dynamic credentials already authenticate the run as
# the phase-specific SA (plan -> <prefix>-bootstrap-plan, apply -> terraform-admin),
# and a null impersonate_service_account means "use the ambient credentials".
# Set it only for a local human re-apply (phase-0 first apply: leave it null and
# run as your own admin credentials while the SA is created).
provider "google" {
  region                      = var.default_region
  impersonate_service_account = var.terraform_admin_email
}

provider "google-beta" {
  region                      = var.default_region
  impersonate_service_account = var.terraform_admin_email
}

provider "random" {}
