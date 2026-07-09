# A workload root has ONE default provider. The region comes from var.aws_region so
# the same root can be pointed at any region without code edits.
provider "aws" {
  region = var.aws_region
}

# Cross-account roots add one aliased provider PER FIXED FOUNDATIONAL ACCOUNT
# (never per workload — workloads fan out by workspace). Role ARNs come from
# the aws-organization remote state (two-phase bootstrap), known at plan time.
# provider "aws" {
#   alias  = "security_tooling"
#   region = var.aws_region
#   assume_role { role_arn = data.terraform_remote_state.aws_organization.outputs.account_role_arns["security_tooling"] }
# }
