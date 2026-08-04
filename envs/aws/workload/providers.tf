# Phase-3 per-env workload root. BOTH providers assume the SAME per-env workload
# account role (published by the aws-organization root's remote state, keyed by
# var.workload_account_key). The default provider operates in the workload's home
# region; the us_east_1 alias operates in us-east-1 (same account) for the
# optional edge-security module's CloudFront/WAF/ACM resources.
#
# Declares ONLY the aws provider — no supabase/vercel (SaaS lives in envs/saas).
provider "aws" {
  region = var.aws_region
  assume_role {
    role_arn = data.terraform_remote_state.aws_organization.outputs.account_role_arns[var.workload_account_key]
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = data.terraform_remote_state.aws_organization.outputs.account_role_arns[var.workload_account_key]
  }
}
