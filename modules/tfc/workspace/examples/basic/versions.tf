terraform {
  required_version = ">= 1.17, < 2.0"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = ">= 0.83.0, < 1.0.0"
    }
  }
}
