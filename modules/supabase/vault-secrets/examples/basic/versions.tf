terraform {
  required_version = "~> 1.9"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# The null provider requires no credentials.
provider "null" {}
