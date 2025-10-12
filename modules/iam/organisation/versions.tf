terraform {
  required_version = ">= 1.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.6"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 4.80"
    }
  }
}

