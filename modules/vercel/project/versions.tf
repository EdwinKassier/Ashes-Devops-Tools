terraform {
  required_version = "~> 1.11"

  required_providers {
    vercel = {
      source  = "vercel/vercel"
      version = "~> 4.0"
    }
  }
}
