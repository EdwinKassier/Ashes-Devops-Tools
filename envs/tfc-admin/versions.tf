terraform {
  required_version = "~> 1.11"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.60"
    }
  }
}
