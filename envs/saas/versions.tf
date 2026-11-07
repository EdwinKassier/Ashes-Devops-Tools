terraform {
  required_version = ">= 1.17, < 2.0"

  # SaaS-only root: NO aws / google providers by design. A user who only wants
  # Supabase and/or Vercel needs no cloud credentials to plan or apply this root.
  required_providers {
    supabase = {
      source  = "supabase/supabase"
      version = "~> 1.0"
    }
    vercel = {
      source  = "vercel/vercel"
      version = ">= 4.8.2, < 5.0.0"
    }
    # MIGRATION ONLY: modules/supabase/vault-secrets now uses built-in
    # terraform_data and no longer needs hashicorp/null. It stays declared (and
    # pinned in the lockfile) because workspaces created before 2026-11 hold
    # null_resource state, and Terraform needs this provider to execute the
    # module's null_resource -> terraform_data `moved` blocks. Remove once every
    # saas-* workspace has applied the move.
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}
