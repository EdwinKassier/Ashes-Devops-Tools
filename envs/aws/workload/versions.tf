terraform {
  required_version = ">= 1.17, < 2.0"

  required_providers {
    tfe = {
      source = "hashicorp/tfe"
      # ephemeral "tfe_outputs" (the SaaS secret bridge) needs >= 0.65; the
      # floor matches tfc-admin so the provider locks at one version repo-wide.
      version = ">= 0.83.0, < 1.0.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.46.0, < 7.0.0"
    }
  }
}
