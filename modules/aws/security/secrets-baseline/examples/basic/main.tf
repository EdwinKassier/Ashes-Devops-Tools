# Basic working example for the aws/secrets-baseline module.
# Enables the baseline with one plain secret and one rotating secret. Run
# `terraform init && terraform validate` here to check it.

module "secrets_baseline" {
  source = "../../"

  enable_secrets_baseline = true
  org_id                  = "o-exampleorgid"

  secrets = {
    "example/db-password" = {}
    "example/api-key" = {
      rotation_lambda_arn = "arn:aws:lambda:us-east-1:111122223333:function:rotate-example"
      rotation_days       = 30
    }
  }
}
