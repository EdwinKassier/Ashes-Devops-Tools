# Basic working example for the aws-shared-services stage.
#
# The stage runs entirely in the SHARED SERVICES account with a SINGLE default
# provider. In a real deployment the provider assumes a role in the shared
# services account; here it uses ambient credentials for a validate-only check.
# Both capabilities are enabled here to exercise the full composition. Run
# `terraform init && terraform validate` in this directory.

provider "aws" {
  region = "eu-west-2"
  # assume_role { role_arn = "arn:aws:iam::222222222222:role/tfc-run-role" }
}

module "aws_shared_services" {
  source = "../../"

  # ACM Private CA — org-shared internal certificate authority.
  enable_private_ca = true
  ca_common_name    = "ashes-internal-ca"
  share_ca_org      = true
  org_arn           = "arn:aws:organizations::111111111111:organization/o-abc1234567"

  # Secrets Manager baseline — org-scoped secrets.
  enable_secrets_baseline = true
  org_id                  = "o-abc1234567"
  secrets = {
    "app/db-password" = {}
  }
}
