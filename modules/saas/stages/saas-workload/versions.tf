terraform {
  required_version = ">= 1.17, < 2.0"

  required_providers {
    supabase = {
      source  = "supabase/supabase"
      version = "~> 1.0"
    }
    vercel = {
      source  = "vercel/vercel"
      version = ">= 4.8.2, < 5.0.0"
    }
  }
}
