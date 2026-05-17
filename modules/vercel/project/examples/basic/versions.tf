terraform {
  required_version = "~> 1.9"

  required_providers {
    vercel = {
      source  = "vercel/vercel"
      version = "~> 5.2"
    }
  }
}

# Provider configured via VERCEL_API_TOKEN environment variable.
# export VERCEL_API_TOKEN="<your-token>"
provider "vercel" {}
