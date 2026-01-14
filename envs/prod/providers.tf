terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.16"
    }
  }
  required_version = ">= 1.5.7"
}

provider "google" {
  region = "europe-west1"
  # Impersonate the Terraform Service Account created in the bootstrap phase
  # In a real TFC setup, this might be handled via Dynamic Credentials env vars
  # alias = "impersonated"
}
