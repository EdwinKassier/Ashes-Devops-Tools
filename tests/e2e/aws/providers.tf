# Real provider: credentials come from the standard AWS SDK chain. In CI that is
# the short-lived session minted by aws-actions/configure-aws-credentials via
# GitHub OIDC (no access keys); locally it is AWS_PROFILE / SSO.
#
# default_tags stamps every taggable resource with the run id so the workflow's
# always() safety-net step can find and delete anything a failed `terraform
# test` teardown leaves behind (resourcegroupstaggingapi, scoped to this tag).
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      "e2e-run-id" = var.run_id
      "managed-by" = "terraform-e2e"
    }
  }
}
