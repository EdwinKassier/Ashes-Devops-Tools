terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.0, < 8.0"
    }
  }
  required_version = "~> 1.9"
}

provider "google" {
  region                      = var.provider_region
  impersonate_service_account = var.terraform_admin_email
}

provider "google-beta" {
  region                      = var.provider_region
  impersonate_service_account = var.terraform_admin_email
}
