# The provider impersonates the Terraform admin SA, exactly as the other GCP
# roots do. On the very first bootstrap apply the SA does not exist yet, so set
# terraform_admin_email = null and run as the caller's own credentials; set it to
# the SA email on subsequent applies.
provider "google" {
  region                      = var.default_region
  impersonate_service_account = var.terraform_admin_email
}

provider "google-beta" {
  region                      = var.default_region
  impersonate_service_account = var.terraform_admin_email
}

provider "random" {}
