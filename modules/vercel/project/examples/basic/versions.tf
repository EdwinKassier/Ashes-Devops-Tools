terraform {
  required_version = ">= 1.17, < 2.0"

  required_providers {
    vercel = {
      source  = "vercel/vercel"
      version = ">= 4.8.2, < 5.0.0"
    }
  }
}

# Provider configured via VERCEL_API_TOKEN environment variable.
# export VERCEL_API_TOKEN="<your-token>"
provider "vercel" {}
