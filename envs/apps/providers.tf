terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.6.0, < 2.0.0"
}

provider "google" {
  region                      = var.provider_region
  impersonate_service_account = var.terraform_admin_email
}
