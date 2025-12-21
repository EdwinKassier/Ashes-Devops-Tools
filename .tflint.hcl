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
  version = "0.37.1"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
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

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"

  custom = "default"

  local {
    format = "snake_case"
  }

  output {
    format = "snake_case"
  }

  variable {
    format = "snake_case"
  }
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


# Disable rules that may be too strict
rule "terraform_module_version" {
  enabled = false
}

