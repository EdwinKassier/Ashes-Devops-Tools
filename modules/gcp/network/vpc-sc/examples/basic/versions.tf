terraform {
  required_version = ">= 1.17, < 2.0"

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
