variable "project_name" {
  description = "Vercel project name. Lowercase alphanumeric and hyphens; 2–100 characters; must not start or end with a hyphen."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,98}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 2–100 characters, lowercase alphanumeric and hyphens, not starting or ending with a hyphen."
  }
}

variable "team_id" {
  description = "Vercel team ID. Required for team-owned projects. Leave empty for personal account projects."
  type        = string
  default     = ""
}

variable "framework" {
  description = "Framework preset applied to the Vercel project. Set null for framework-agnostic projects."
  type        = string
  default     = "nextjs"

  validation {
    # coalesce(var.framework, "nextjs") only skips null — it does NOT skip "".
    # An empty string passes coalesce unchanged, fails contains(), and produces a
    # confusing error. The explicit `var.framework == null` arm short-circuits the
    # list check for the null/"framework-agnostic" case; the second arm rejects
    # empty string explicitly.
    condition = (
      var.framework == null ||
      (var.framework != "" && contains([
        "nextjs", "gatsby", "remix", "astro", "nuxt", "sveltekit",
        "vite", "create-react-app", "angular", "vue", "ember",
        "hugo", "eleventy", "jekyll", "blitzjs", "redwoodjs",
      ], var.framework))
    )
    error_message = "framework must be a valid Vercel framework preset, or null for framework-agnostic projects. Empty string is not accepted — use null."
  }
}

variable "github_repo" {
  description = "GitHub repository in 'org/repo' format (e.g. 'myorg/myrepo')."
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repo))
    error_message = "github_repo must be in 'org/repo' format."
  }
}

variable "production_branch" {
  description = <<-EOT
    Git branch to deploy to the production environment.
    ⚠️  Must be an existing branch — Vercel validates branch existence at apply time.
    Setting a non-existent branch name will fail. Default "main" is safe for most repos.
  EOT
  type        = string
  default     = "main"

  validation {
    condition     = length(var.production_branch) >= 1
    error_message = "production_branch must not be empty."
  }
}

variable "root_directory" {
  description = <<-EOT
    Root directory of the project within the repository (e.g. "apps/nextjs" for a monorepo).
    Leave empty ("") for the repository root. The module converts "" to null internally —
    the Vercel API rejects an empty string with invalid_root_directory.
  EOT
  type        = string
  default     = ""
}

variable "serverless_function_region" {
  description = "Region for serverless function execution. Must be a valid Vercel function region code."
  type        = string
  default     = "lhr1"

  validation {
    condition = contains([
      "iad1", "sfo1", "pdx1", "sea1", "lhr1", "cdg1", "fra1",
      "bom1", "sin1", "kix1", "cle1", "hnd1", "gru1", "icn1",
      "dub1", "cpt1",
    ], var.serverless_function_region)
    error_message = "serverless_function_region must be a valid Vercel edge network region (e.g. 'lhr1', 'iad1')."
  }
}

variable "allowed_branches" {
  description = <<-EOT
    Git branches that trigger deployments. Builds on all other branches are skipped.
    The module generates an ignore_command using POSIX sh syntax (not bash) — Vercel
    executes this in /bin/sh. Do not add bash-specific syntax ([[ ]], ==).
    Must contain at least one branch name.
  EOT
  type        = list(string)
  default     = ["main"]

  validation {
    condition     = length(var.allowed_branches) >= 1
    error_message = "allowed_branches must contain at least one branch name."
  }
}

variable "domains" {
  description = <<-EOT
    Domain assignments for the project. Each entry maps a domain to an environment.
    environment must be one of: "qa", "uat", "production".
  EOT
  type = list(object({
    domain      = string
    environment = string
  }))
  default = []

  validation {
    condition = alltrue([
      for d in var.domains : contains(["qa", "uat", "production"], d.environment)
    ])
    error_message = "Each domain's environment must be one of: qa, uat, production."
  }
}

variable "qa_environment_variables" {
  description = "Environment variables for the QA (preview) environment. key and value are required; sensitive defaults to false."
  type = list(object({
    key       = string
    value     = string
    sensitive = optional(bool, false)
  }))
  default = []
}

variable "uat_environment_variables" {
  description = "Environment variables for the UAT custom environment. key and value are required; sensitive defaults to false."
  type = list(object({
    key       = string
    value     = string
    sensitive = optional(bool, false)
  }))
  default = []
}

variable "prod_environment_variables" {
  description = "Environment variables for the production environment. key and value are required; sensitive defaults to false."
  type = list(object({
    key       = string
    value     = string
    sensitive = optional(bool, false)
  }))
  default = []
}

variable "shared_environment_variables" {
  description = "Environment variables applied to all three environments (QA, UAT, production). Useful for SSL certs and global feature flags."
  type = list(object({
    key       = string
    value     = string
    sensitive = optional(bool, false)
  }))
  default = []
}
