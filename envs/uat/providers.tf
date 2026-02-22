terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.20"
    }
  }
  required_version = ">= 1.5.7"
}

provider "google" {
  region = "europe-west1"
}
