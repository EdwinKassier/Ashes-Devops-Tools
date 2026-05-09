terraform {
  required_version = "~> 1.9"

  required_providers {
    supabase = {
      source  = "supabase/supabase"
      version = "~> 1.0"
    }
  }
}

# Provider configured via SUPABASE_ACCESS_TOKEN environment variable.
# export SUPABASE_ACCESS_TOKEN="<your-token>"
provider "supabase" {}
