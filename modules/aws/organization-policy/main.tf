# AWS Organizations guardrail policies for the SRA landing zone.
#
# Renders a set of organization policies from templated JSON files and attaches
# them to OU/account targets. Covers all five Organizations policy types:
#   - SERVICE_CONTROL_POLICY (SCP)   — deny-tamper, region-restriction, baseline
#   - RESOURCE_CONTROL_POLICY (RCP)  — two-statement data perimeter + TLS
#   - DECLARATIVE_POLICY_EC2         — IMDSv2 + public-access blocks (@@assign)
#   - TAG_POLICY                     — required cost/ownership tag keys
#   - BACKUP_POLICY                  — a sensible daily backup plan
#
# The policy content strings are computed here in locals (a variable `default`
# cannot reference var.* or path.module, both of which the templatefile renders
# need). Callers can override the whole set by passing a non-empty `policies`.
#
# FullAWSAccess / RCPFullAWSAccess are AWS-managed and deliberately never
# managed here.

locals {
  default_policies = {
    scp-deny-tamper = {
      type = "SERVICE_CONTROL_POLICY"
      content = templatefile("${path.module}/policies/scp-deny-tamper.json", {
        terraform_run_role_arn  = var.terraform_run_role_arn
        break_glass_role_arn    = var.break_glass_role_arn
        log_archive_bucket_name = var.log_archive_bucket_name
      })
    }
    scp-region-restriction = {
      type = "SERVICE_CONTROL_POLICY"
      content = templatefile("${path.module}/policies/scp-region-restriction.json", {
        allowed_regions        = jsonencode(var.allowed_regions)
        terraform_run_role_arn = var.terraform_run_role_arn
        break_glass_role_arn   = var.break_glass_role_arn
      })
    }
    scp-baseline = {
      type = "SERVICE_CONTROL_POLICY"
      content = templatefile("${path.module}/policies/scp-baseline.json", {
        terraform_run_role_arn = var.terraform_run_role_arn
        break_glass_role_arn   = var.break_glass_role_arn
      })
    }
    rcp-data-perimeter = {
      type = "RESOURCE_CONTROL_POLICY"
      content = templatefile("${path.module}/policies/rcp-data-perimeter.json", {
        org_id = var.org_id
      })
    }
    declarative-ec2 = {
      type    = "DECLARATIVE_POLICY_EC2"
      content = templatefile("${path.module}/policies/declarative-ec2.json", {})
    }
    tag-policy = {
      type    = "TAG_POLICY"
      content = templatefile("${path.module}/policies/tag-policy.json", {})
    }
    backup-policy = {
      type = "BACKUP_POLICY"
      content = templatefile("${path.module}/policies/backup-policy.json", {
        default_region = var.default_region
      })
    }
  }

  effective_policies = length(var.policies) > 0 ? var.policies : local.default_policies
}

resource "aws_organizations_policy" "policy" {
  for_each = local.effective_policies
  name     = each.key
  type     = each.value.type
  content  = each.value.content
}

resource "aws_organizations_policy_attachment" "attach" {
  for_each  = var.attachments
  policy_id = aws_organizations_policy.policy[each.value.policy_key].id
  target_id = each.value.target_id
}
