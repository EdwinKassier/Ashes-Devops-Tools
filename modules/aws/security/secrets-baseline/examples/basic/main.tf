# Basic working example for the aws/secrets-baseline module.
# Enables the baseline with one plain secret and one rotating secret, both
# encrypted with a customer-managed KMS key. Run
# `terraform init && terraform validate` here to check it.

module "secrets_baseline" {
  source = "../../"

  enable_secrets_baseline = true
  org_id                  = "o-exampleorgid"
  kms_key_id              = "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"

  secrets = {
    "example/db-password" = {}
    "example/api-key" = {
      rotation_lambda_arn = "arn:aws:lambda:eu-west-2:111111111111:function:rotate-example"
      rotation_days       = 30
    }
  }
}
