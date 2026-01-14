variable "terraform_admin_email" {
  description = "Email of the Terraform Admin Service Account to impersonate"
  type        = string
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.16"
    }
  }
}

# Provider configuration that uses the user's local credentials to get an access token for the service account
provider "google" {
  alias = "impersonation"
  scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/userinfo.email",
  ]
}

data "google_service_account_access_token" "default" {
  provider               = google.impersonation
  target_service_account = var.terraform_admin_email
  scopes                 = ["userinfo-email", "cloud-platform"]
  lifetime               = "1200s"
}

provider "google" {
  access_token = data.google_service_account_access_token.default.access_token
  region       = "europe-west1"
}
