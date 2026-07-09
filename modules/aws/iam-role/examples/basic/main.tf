# Basic working example for the aws/iam-role module.
# Defines one cross-account workload role plus the disabled-by-default
# break-glass role. Run `terraform init && terraform validate` here to check it.

module "iam_role" {
  source = "../../"

  roles = {
    cross-account-audit = {
      trust_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::111111111111:root" }
          Action    = "sts:AssumeRole"
        }]
      })
      max_session_duration = 3600
      managed_policy_arns  = ["arn:aws:iam::aws:policy/SecurityAudit"]
    }
  }

  break_glass_trusted_principals = ["arn:aws:iam::222222222222:role/incident-commander"]
}
