terraform {
  required_version = "~> 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  impersonate_service_account = "terraform@my-seed-project.iam.gserviceaccount.com"
}
