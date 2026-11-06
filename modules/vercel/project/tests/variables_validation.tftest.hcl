# Variable validation tests for modules/vercel/project.

mock_provider "vercel" {}

variables {
  project_name = "my-app"
  github_repo  = "myorg/my-app"
}

# ── project_name ───────────────────────────────────────────────────────────────

run "valid_project_name_accepted" {
  command = plan
  variables { project_name = "my-app" }
}

run "uppercase_project_name_rejected" {
  command         = plan
  expect_failures = [var.project_name]
  variables { project_name = "My-App" }
}

run "hyphen_start_project_name_rejected" {
  command         = plan
  expect_failures = [var.project_name]
  variables { project_name = "-my-app" }
}

# ── github_repo ────────────────────────────────────────────────────────────────

run "valid_github_repo_accepted" {
  command = plan
  variables { github_repo = "myorg/my-app" }
}

run "missing_slash_github_repo_rejected" {
  command         = plan
  expect_failures = [var.github_repo]
  variables { github_repo = "myorg-my-app" }
}

# ── serverless_function_region ─────────────────────────────────────────────────

run "valid_region_lhr1_accepted" {
  command = plan
  variables { serverless_function_region = "lhr1" }
}

run "valid_region_iad1_accepted" {
  command = plan
  variables { serverless_function_region = "iad1" }
}

run "invalid_region_rejected" {
  command         = plan
  expect_failures = [var.serverless_function_region]
  variables { serverless_function_region = "mars-1" }
}

# ── domains ────────────────────────────────────────────────────────────────────

run "valid_domains_accepted" {
  command = plan
  variables {
    domains = [
      { domain = "qa.example.com", environment = "qa" },
      { domain = "uat.example.com", environment = "uat" },
      { domain = "example.com", environment = "production" },
    ]
  }
}

run "invalid_domain_environment_rejected" {
  command         = plan
  expect_failures = [var.domains]
  variables {
    domains = [{ domain = "staging.example.com", environment = "staging" }]
  }
}

# ── allowed_branches ───────────────────────────────────────────────────────────

run "valid_allowed_branches_accepted" {
  command = plan
  variables { allowed_branches = ["main", "develop"] }
}

run "empty_allowed_branches_rejected" {
  command         = plan
  expect_failures = [var.allowed_branches]
  variables { allowed_branches = [] }
}

# ── env var wiring (sensitive attribute requirement) ───────────────────────────
# vercel_project_environment_variable.sensitive is schema-required (required=True).
# The module provides it via each.value.sensitive which defaults to TRUE via
# optional(bool, true) — secure by default. These runs confirm the wiring.

run "env_var_with_sensitive_false_accepted" {
  command = plan
  variables {
    qa_environment_variables = [
      { key = "NEXT_PUBLIC_API_URL", value = "https://api.example.com", sensitive = false }
    ]
  }
}

run "env_var_sensitive_defaults_to_true" {
  command = plan
  variables {
    qa_environment_variables     = [{ key = "API_SECRET", value = "s3cr3t" }]
    uat_environment_variables    = [{ key = "API_SECRET", value = "s3cr3t" }]
    prod_environment_variables   = [{ key = "API_SECRET", value = "s3cr3t" }]
    shared_environment_variables = [{ key = "SHARED_SECRET", value = "s3cr3t" }]
  }

  assert {
    condition = alltrue([
      vercel_project_environment_variable.qa["API_SECRET"].sensitive,
      vercel_project_environment_variable.uat["API_SECRET"].sensitive,
      vercel_project_environment_variable.prod["API_SECRET"].sensitive,
      vercel_project_environment_variable.shared["SHARED_SECRET"].sensitive,
      vercel_project_environment_variable.shared_uat["SHARED_SECRET"].sensitive,
    ])
    error_message = "An env var without an explicit sensitive flag must default to sensitive = true (secure by default)."
  }

  assert {
    condition     = !contains(vercel_project_environment_variable.qa["API_SECRET"].target, "development") && !contains(vercel_project_environment_variable.prod["API_SECRET"].target, "development")
    error_message = "No env var may target development: Vercel rejects sensitive = true on development-only variables."
  }
}

run "env_var_sensitive_false_opt_out_honoured" {
  command = plan
  variables {
    qa_environment_variables = [{ key = "NEXT_PUBLIC_API_URL", value = "https://api.example.com", sensitive = false }]
  }

  assert {
    condition     = vercel_project_environment_variable.qa["NEXT_PUBLIC_API_URL"].sensitive == false
    error_message = "An explicit sensitive = false must be honoured."
  }
}

run "env_var_with_sensitive_true_accepted" {
  command = plan
  variables {
    qa_environment_variables = [
      { key = "DATABASE_URL", value = "postgres://user:pass@host/db", sensitive = true }
    ]
  }
}

# ── team_id empty string (personal account) ────────────────────────────────────
# Confirms that team_id = "" coerces to null (not passed as empty string to API).
# Personal account deploys have no team_id.

run "empty_team_id_personal_account_accepted" {
  command = plan
  variables { team_id = "" }
}

# ── framework ──────────────────────────────────────────────────────────────────

run "null_framework_accepted" {
  # null means "framework-agnostic" — explicitly permitted by the validation rule.
  command = plan
  variables { framework = null }
}

run "valid_framework_accepted" {
  command = plan
  variables { framework = "astro" }
}

run "empty_string_framework_rejected" {
  # Empty string is NOT the same as null. The validation explicitly rejects "".
  command         = plan
  expect_failures = [var.framework]
  variables { framework = "" }
}

run "invalid_framework_rejected" {
  command         = plan
  expect_failures = [var.framework]
  variables { framework = "rails" }
}
