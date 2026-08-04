terraform {
  required_version = "~> 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }
}

provider "google" {
  impersonate_service_account = "terraform@my-seed-project.iam.gserviceaccount.com"
}
