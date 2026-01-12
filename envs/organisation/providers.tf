terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.15"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  required_version = ">= 1.5.7"
}

provider "google" {
  # Configuration options
  region = var.default_region
}

provider "google-beta" {
  # Configuration options for beta resources
  region = var.default_region
}

provider "random" {}

# You can add more provider configurations here if needed
