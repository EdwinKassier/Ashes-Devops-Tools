terraform {
  required_version = "~> 1.9"

  # SaaS-only root: NO aws / google providers by design. A user who only wants
  # Supabase and/or Vercel needs no cloud credentials to plan or apply this root.
  required_providers {
    supabase = {
      source  = "supabase/supabase"
      version = "~> 1.0"
    }
    vercel = {
      source  = "vercel/vercel"
      version = "~> 4.0"
    }
    # Required transitively by modules/stages/saas-workload (vault-secrets uses
    # null_resource). Declared even when enable_vault_secrets = false because a
    # provider requirement cannot be made conditional.
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}
