# Vercel Project Module
#
# Creates a Vercel project with three environments:
#   - QA    → Vercel "preview" environment (deploys from production_branch)
#   - UAT   → Vercel custom environment named "uat" (Pro plan: 1 custom env per project)
#   - Prod  → Vercel "production" environment
#
# SENSITIVE ENV VAR DRIFT:
#   Vercel's API does not return sensitive variable values after creation.
#   Terraform cannot detect value drift for sensitive vars. This module uses
#   terraform_data resources with replace_triggered_by keyed on SHA256 hashes
#   of all env var values. Any value change forces replacement of the entire
#   env var set for that environment — ensuring drift never goes silent.
#
# POSIX SH:
#   ignore_command is executed in /bin/sh by Vercel (not bash). All
#   comparisons use [ ] and = (not [[ ]] or ==).
#
# ROOT DIRECTORY:
#   The Vercel API rejects empty string as invalid_root_directory. This module
#   converts var.root_directory == "" to null before passing to the resource.
#
# PLAN LIMITS:
#   Pro plan supports 1 custom environment per project. The UAT environment
#   consumes this slot. Do not add additional vercel_custom_environment resources
#   without upgrading to an Enterprise plan.

locals {
  root_directory_normalized = var.root_directory != "" ? var.root_directory : null

  # POSIX sh ignore_command: Vercel semantics are exit 1 = build, exit 0 = skip.
  # The command builds the branch if it's in allowed_branches; otherwise skips.
  #
  # Uses POSIX sh syntax: [ ... ] and = (not bash [[ ... ]] or ==).
  # Vercel executes ignore_command in /bin/sh — bash extensions throw a syntax
  # error in sh, silently disabling the filter and triggering builds on every
  # branch regardless of allowed_branches.
  #
  # Multi-branch: join conditions with ] || [ to chain POSIX-compatible tests
  # inside a single if statement. This mirrors the collects reference exactly.
  #
  # Empty allowed_branches is rejected by var.allowed_branches validation
  # (length >= 1 required), so the length == 0 branch is unreachable here
  # but retained for defensive completeness.
  branch_checks  = join(" ] || [ \"$VERCEL_GIT_COMMIT_REF\" = ", [
    for b in var.allowed_branches : "\"${b}\""
  ])
  ignore_command = length(var.allowed_branches) == 0 ? "exit 0" : (
    "if [ \"$VERCEL_GIT_COMMIT_REF\" = ${local.branch_checks} ]; then exit 1; else exit 0; fi"
  )

  # Order-independent fingerprints for SHA256 drift detection.
  #
  # Vercel's API does not return sensitive variable values after creation —
  # Terraform cannot diff the stored value on subsequent applies. These
  # fingerprints hash every env var key=value pair so any value change is
  # detected and replace_triggered_by forces full env var replacement.
  #
  # nonsensitive(sha256(...)): the input lists are tainted sensitive because
  # they contain values derived from sensitive inputs (e.g. POSTGRES_URL
  # containing database_password). sha256 is one-way so exposing the digest
  # leaks nothing — but NOT wrapping it would store a sensitive value in
  # terraform_data.input and show "(sensitive value) → (sensitive value)" in
  # plan output, making it impossible to verify that a replace_triggered_by
  # event was caused by an intentional change. nonsensitive() strips the taint
  # from the hash so the transition "a3f1... → b2c4..." is visible in plan.
  #
  # Sorting key=value strings before hashing is order-independent: reordering
  # items in the variable definition (a refactor with no semantic effect) must
  # not flip the hash and force unnecessary Vercel env var replacements.
  qa_vars_fingerprint     = nonsensitive(sha256(join("\n", sort([for v in var.qa_environment_variables     : "${v.key}=${v.value}"]))))
  uat_vars_fingerprint    = nonsensitive(sha256(join("\n", sort([for v in var.uat_environment_variables    : "${v.key}=${v.value}"]))))
  prod_vars_fingerprint   = nonsensitive(sha256(join("\n", sort([for v in var.prod_environment_variables   : "${v.key}=${v.value}"]))))
  shared_vars_fingerprint = nonsensitive(sha256(join("\n", sort([for v in var.shared_environment_variables : "${v.key}=${v.value}"]))))

  # Convert env var lists to maps keyed by variable name for for_each.
  qa_vars_map     = { for v in var.qa_environment_variables : v.key => v }
  uat_vars_map    = { for v in var.uat_environment_variables : v.key => v }
  prod_vars_map   = { for v in var.prod_environment_variables : v.key => v }
  shared_vars_map = { for v in var.shared_environment_variables : v.key => v }

  # Domains partitioned by environment.
  qa_domains   = [for d in var.domains : d if d.environment == "qa"]
  uat_domains  = [for d in var.domains : d if d.environment == "uat"]
  prod_domains = [for d in var.domains : d if d.environment == "production"]
}

resource "vercel_project" "this" {
  name    = var.project_name
  team_id = var.team_id != "" ? var.team_id : null

  framework                  = var.framework
  root_directory             = local.root_directory_normalized
  ignore_command             = local.ignore_command
  serverless_function_region = var.serverless_function_region

  # git_repository is a Single Nested Attribute in the Vercel provider v4 schema
  # — it requires = { } assignment syntax, NOT block syntax (without =).
  # Using block syntax produces: "An argument named 'git_repository' is not expected here."
  git_repository = {
    type              = "github"
    repo              = var.github_repo
    production_branch = var.production_branch
  }
}

resource "vercel_custom_environment" "uat" {
  project_id  = vercel_project.this.id
  team_id     = var.team_id != "" ? var.team_id : null
  name        = "uat"
  description = "UAT (user acceptance testing) environment — mirrors production at next-release state."
}

# ── Drift-resistance triggers ───────────────────────────────────────────────────
#
# Vercel's API does not return sensitive variable values after creation.
# These terraform_data resources store a SHA256 hash of all env var key=values.
# When any value changes, the hash changes, replace_triggered_by fires, and the
# entire env var set for that environment is replaced — preventing silent drift.

resource "terraform_data" "qa_vars_version" {
  input = local.qa_vars_fingerprint
}

resource "terraform_data" "uat_vars_version" {
  input = local.uat_vars_fingerprint
}

resource "terraform_data" "prod_vars_version" {
  input = local.prod_vars_fingerprint
}

resource "terraform_data" "shared_vars_version" {
  input = local.shared_vars_fingerprint
}

# ── QA environment variables (preview) ─────────────────────────────────────────

resource "vercel_project_environment_variable" "qa" {
  for_each = nonsensitive(local.qa_vars_map)

  project_id = vercel_project.this.id
  team_id    = var.team_id != "" ? var.team_id : null
  key        = each.key
  value      = each.value.value   # provider marks `value` sensitive in schema — no wrapper needed
  target     = ["preview"]
  sensitive  = each.value.sensitive

  lifecycle {
    replace_triggered_by = [terraform_data.qa_vars_version]
  }
}

# ── UAT environment variables (custom environment) ──────────────────────────────
#
# target = [] is required when assigning vars to a custom environment only.
# The Vercel API uses custom_environment_ids to route the assignment;
# target must be empty or Vercel creates conflicting preview/production copies.

resource "vercel_project_environment_variable" "uat" {
  for_each = nonsensitive(local.uat_vars_map)

  project_id             = vercel_project.this.id
  team_id                = var.team_id != "" ? var.team_id : null
  key                    = each.key
  value                  = each.value.value   # provider marks `value` sensitive in schema — no wrapper needed
  target                 = []
  custom_environment_ids = [vercel_custom_environment.uat.id]
  sensitive              = each.value.sensitive

  lifecycle {
    replace_triggered_by = [terraform_data.uat_vars_version]
  }
}

# ── Production environment variables ───────────────────────────────────────────

resource "vercel_project_environment_variable" "prod" {
  for_each = nonsensitive(local.prod_vars_map)

  project_id = vercel_project.this.id
  team_id    = var.team_id != "" ? var.team_id : null
  key        = each.key
  value      = each.value.value   # provider marks `value` sensitive in schema — no wrapper needed
  target     = ["production"]
  sensitive  = each.value.sensitive

  lifecycle {
    replace_triggered_by = [terraform_data.prod_vars_version]
  }
}

# ── Shared environment variables (all three environments) ───────────────────────

resource "vercel_project_environment_variable" "shared" {
  for_each = nonsensitive(local.shared_vars_map)

  project_id             = vercel_project.this.id
  team_id                = var.team_id != "" ? var.team_id : null
  key                    = each.key
  value                  = each.value.value   # provider marks `value` sensitive in schema — no wrapper needed
  target                 = ["preview", "production"]
  custom_environment_ids = [vercel_custom_environment.uat.id]
  sensitive              = each.value.sensitive

  lifecycle {
    replace_triggered_by = [terraform_data.shared_vars_version]
  }
}

# ── Domain assignments ──────────────────────────────────────────────────────────

resource "vercel_project_domain" "qa" {
  for_each = { for d in local.qa_domains : d.domain => d }

  project_id = vercel_project.this.id
  team_id    = var.team_id != "" ? var.team_id : null
  domain     = each.key
  # git_branch intentionally omitted: the QA environment is Vercel "preview" (any branch).
  # Setting git_branch restricts the domain to deployments from one specific branch only —
  # defeating its purpose as a QA domain accessible from all preview builds.
  # (Collects hardcodes git_branch = "main" on the QA domain; that is a design gap we
  # intentionally fix here by omitting it and letting all preview builds resolve the domain.)
}

resource "vercel_project_domain" "uat" {
  for_each = { for d in local.uat_domains : d.domain => d }

  project_id            = vercel_project.this.id
  team_id               = var.team_id != "" ? var.team_id : null
  domain                = each.key
  custom_environment_id = vercel_custom_environment.uat.id
}

resource "vercel_project_domain" "prod" {
  for_each = { for d in local.prod_domains : d.domain => d }

  project_id = vercel_project.this.id
  team_id    = var.team_id != "" ? var.team_id : null
  domain     = each.key
}
