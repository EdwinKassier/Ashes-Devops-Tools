config {
  call_module_type = "all"
  force               = false
  disabled_by_default = false

  varfile = []
  variables = []
}

# GCP Plugin
plugin "google" {
  enabled = true
  version = "0.39.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

# AWS Plugin — rules only match aws_* resources, so enabling it repo-wide is a
# no-op for GCP/SaaS modules. Covers the ~49 AWS modules (invalid instance
# types, deprecated arguments, invalid enum values the provider would reject
# only at apply time). Bump `version` together with the google ruleset.
plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Terraform Plugin
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Rules for Terraform Best Practices
rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_comment_syntax" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
  style   = "semver"
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_standard_module_structure" {
  enabled = true
}

rule "terraform_workspace_remote" {
  enabled = true
}

rule "terraform_module_version" {
  enabled = true
}
