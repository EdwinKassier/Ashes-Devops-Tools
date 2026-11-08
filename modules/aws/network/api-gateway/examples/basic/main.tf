# Basic working example for the aws/api-gateway module.
# Creates an HTTP API with one Lambda-proxy route, restricted CORS and an
# auto-deployed $default stage. Routes keep the module's secure default of
# AWS_IAM authorization, and the access-log group is encrypted with a
# customer-managed KMS key. Run `terraform init && terraform validate` here to
# check it.
#
# The Lambda and KMS key ARNs are placeholders: replace them with your own.

module "api_gateway" {
  source = "../../"

  name          = "orders-api"
  protocol_type = "HTTP"
  description   = "Orders HTTP API (example)."

  cors_configuration = {
    allow_origins = ["https://app.example.com"]
    allow_methods = ["GET", "POST"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 300
  }

  routes = [
    {
      route_key       = "GET /orders"
      integration_uri = "arn:aws:lambda:eu-west-2:111122223333:function:list-orders"
      # authorization_type defaults to AWS_IAM (SigV4-signed callers only).
    },
  ]

  log_retention_days = 365
  kms_key_arn        = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"

  tags = {
    environment = "dev"
  }
}
