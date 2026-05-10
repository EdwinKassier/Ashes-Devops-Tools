provider "google" {
  region                      = var.region
  impersonate_service_account = var.terraform_admin_email
}

provider "google-beta" {
  region                      = var.region
  impersonate_service_account = var.terraform_admin_email
}
