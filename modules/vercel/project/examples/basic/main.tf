# Example: create a Vercel project with QA/UAT/production environments,
# Supabase environment variables, and custom domains.
# Replace locals with real values or remote state outputs.

locals {
  team_id     = "team_abcdefghijklmno"
  github_repo = "myorg/my-app"

  # In production, these come from supabase/environment module outputs
  # or terraform_remote_state.
  qa_supabase_url     = "https://qarefabcdefghij.supabase.co"
  qa_supabase_anon    = "eyJhbGciOiJIUzI1NiJ9.qa_anon_key..."
  uat_supabase_url    = "https://uatrefabcdefghij.supabase.co"
  uat_supabase_anon   = "eyJhbGciOiJIUzI1NiJ9.uat_anon_key..."
  prod_supabase_url   = "https://prodrefabcdefghij.supabase.co"
  prod_supabase_anon  = "eyJhbGciOiJIUzI1NiJ9.prod_anon_key..."
}

module "vercel_project" {
  source = "../../"

  project_name               = "my-app"
  team_id                    = local.team_id
  github_repo                = local.github_repo
  production_branch          = "main"
  root_directory             = "apps/nextjs"   # monorepo: set "" for repo root
  serverless_function_region = "lhr1"
  allowed_branches           = ["main"]
  framework                  = "nextjs"

  domains = [
    { domain = "qa.my-app.com",   environment = "qa" },
    { domain = "uat.my-app.com",  environment = "uat" },
    { domain = "my-app.com",      environment = "production" },
    { domain = "www.my-app.com",  environment = "production" },
  ]

  qa_environment_variables = [
    { key = "NEXT_PUBLIC_SUPABASE_URL",      value = local.qa_supabase_url,  sensitive = false },
    { key = "NEXT_PUBLIC_SUPABASE_ANON_KEY", value = local.qa_supabase_anon, sensitive = false },
    { key = "NEXT_PUBLIC_APP_URL",           value = "https://qa.my-app.com", sensitive = false },
  ]

  uat_environment_variables = [
    { key = "NEXT_PUBLIC_SUPABASE_URL",      value = local.uat_supabase_url,  sensitive = false },
    { key = "NEXT_PUBLIC_SUPABASE_ANON_KEY", value = local.uat_supabase_anon, sensitive = false },
    { key = "NEXT_PUBLIC_APP_URL",           value = "https://uat.my-app.com", sensitive = false },
  ]

  prod_environment_variables = [
    { key = "NEXT_PUBLIC_SUPABASE_URL",      value = local.prod_supabase_url,  sensitive = false },
    { key = "NEXT_PUBLIC_SUPABASE_ANON_KEY", value = local.prod_supabase_anon, sensitive = false },
    { key = "NEXT_PUBLIC_APP_URL",           value = "https://my-app.com", sensitive = false },
  ]
}

output "vercel_project_id"    { value = module.vercel_project.project_id }
output "vercel_project_name"  { value = module.vercel_project.project_name }
output "uat_environment_id"   { value = module.vercel_project.uat_environment_id }
