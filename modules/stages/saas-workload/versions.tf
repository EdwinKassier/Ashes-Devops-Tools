terraform {
  required_version = "~> 1.9"

  required_providers {
    supabase = {
      source  = "supabase/supabase"
      version = "~> 1.0"
    }
    vercel = {
      source  = "vercel/vercel"
      version = "~> 5.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}
