terraform {
  required_version = "~> 1.11"

  required_providers {
    tfe = {
      source = "hashicorp/tfe"
      # Floor = the version the lockfile pins and the tests exercise (value_wo,
      # tfe_workspace_settings, policy_tool_version); stay below 1.0 until its
      # breaking changes are reviewed.
      version = ">= 0.83.0, < 1.0.0"
    }
  }
}
