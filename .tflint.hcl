config {
  module              = true
  force               = false
  disabled_by_default = false

  varfile = []
  variables = []
}

# GCP Plugin
plugin "google" {
  enabled = true
  version = "0.26.0"
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

  locals {
    format = "snake_case"
  }

  outputs {
    format = "snake_case"
  }

  variables {
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

# GCP-specific rules
rule "google_compute_disk_invalid_size" {
  enabled = true
}

rule "google_compute_instance_invalid_machine_type" {
  enabled = true
}

rule "google_container_cluster_invalid_machine_type" {
  enabled = true
}

rule "google_project_service_invalid_project" {
  enabled = true
}

rule "google_storage_bucket_invalid_location" {
  enabled = true
}

# Disable rules that may be too strict
rule "terraform_module_version" {
  enabled = false
}

