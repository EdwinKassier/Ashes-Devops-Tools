# Resource-assertion tests for the aws/organization-policy module.
#
# The provider does not parse aws_organizations_policy.content at plan, so these
# assertions inspect the rendered template strings directly. Where practical we
# jsondecode() the rendered content to prove it is valid JSON with the expected
# keys (the raw files carry ${...} placeholders and cannot be parsed standalone).

mock_provider "aws" {}

variables {
  org_id                  = "o-abc1234567"
  allowed_regions         = ["eu-west-2", "eu-west-1"]
  management_account_id   = "111111111111"
  security_account_id     = "222222222222"
  terraform_run_role_arn  = "arn:aws:iam::111111111111:role/tfc-run-role"
  break_glass_role_arn    = "arn:aws:iam::111111111111:role/break-glass"
  log_archive_bucket_name = "sra-log-archive-111111111111"
}

run "guardrail_policies_render_correctly" {
  command = plan

  assert {
    condition     = can(regex("organizations:LeaveOrganization", aws_organizations_policy.policy["scp-deny-tamper"].content))
    error_message = "deny-tamper SCP must deny organizations:LeaveOrganization"
  }

  assert {
    condition     = can(regex("aws:RequestedRegion", aws_organizations_policy.policy["scp-region-restriction"].content))
    error_message = "region-restriction SCP must condition on aws:RequestedRegion"
  }

  assert {
    condition     = can(regex("arn:aws:iam::[*]:root", aws_organizations_policy.policy["scp-baseline"].content))
    error_message = "baseline SCP must deny root-user actions in member accounts"
  }

  assert {
    condition     = aws_organizations_policy.policy["rcp-data-perimeter"].type == "RESOURCE_CONTROL_POLICY"
    error_message = "rcp-data-perimeter must be a RESOURCE_CONTROL_POLICY"
  }

  assert {
    condition     = length(regexall("aws:SourceOrgID", aws_organizations_policy.policy["rcp-data-perimeter"].content)) > 0
    error_message = "RCP must scope the AWS-service exemption with aws:SourceOrgID"
  }

  assert {
    condition     = can(regex("aws:SecureTransport", aws_organizations_policy.policy["rcp-data-perimeter"].content))
    error_message = "RCP must require secure transport"
  }

  assert {
    condition     = can(regex("@@assign", aws_organizations_policy.policy["declarative-ec2"].content))
    error_message = "declarative content must use @@assign syntax"
  }

  # Robust validity check: every rendered content must be valid JSON.
  assert {
    condition     = jsondecode(aws_organizations_policy.policy["scp-deny-tamper"].content).Version == "2012-10-17"
    error_message = "deny-tamper SCP must render to valid IAM policy JSON"
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.policy["rcp-data-perimeter"].content).Statement[0].Principal == "*"
    error_message = "RCP statements must set Principal to *"
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.policy["declarative-ec2"].content).ec2_attributes.instance_metadata_defaults.http_tokens["@@assign"] == "required"
    error_message = "declarative EC2 policy must enforce IMDSv2 (http_tokens required)"
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.policy["tag-policy"].content).tags.CostCenter.tag_key["@@assign"] == "CostCenter"
    error_message = "tag policy must enforce the CostCenter tag key"
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.policy["backup-policy"].content).plans.default.regions["@@assign"][0] == "eu-west-2"
    error_message = "backup policy must target the default region"
  }

  assert {
    condition     = length(keys(aws_organizations_policy.policy)) == 7
    error_message = "the built-in guardrail set must produce all seven policies"
  }
}

run "region_list_renders_into_scp" {
  command = plan

  variables {
    allowed_regions = ["us-east-1", "eu-central-1"]
  }

  assert {
    condition     = contains(jsondecode(aws_organizations_policy.policy["scp-region-restriction"].content).Statement[0].Condition.StringNotEquals["aws:RequestedRegion"], "us-east-1")
    error_message = "allowed_regions list must render into the region-restriction SCP condition"
  }
}

run "attachments_key_correctly" {
  command = plan

  variables {
    attachments = {
      "baseline@root"        = { policy_key = "scp-baseline", target_id = "r-abcd" }
      "data-perimeter@wklds" = { policy_key = "rcp-data-perimeter", target_id = "ou-abcd-11111111" }
    }
  }

  assert {
    condition     = contains(keys(aws_organizations_policy_attachment.attach), "baseline@root")
    error_message = "attachments must key on the caller-provided map key"
  }
}
