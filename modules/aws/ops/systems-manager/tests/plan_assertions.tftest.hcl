# Resource-assertion tests for the aws/systems-manager module.
#
# Asserts on configured attributes that are known at plan time under
# mock_provider: the rendered Session Manager document content, the per-OS
# patch baselines and the Patch Manager scan and install associations.

mock_provider "aws" {}

variables {
  log_bucket_name = "org-ssm-session-logs"
  kms_key_id      = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
}

run "session_document_carries_logging_and_kms" {
  command = plan

  assert {
    condition     = can(regex("org-ssm-session-logs", aws_ssm_document.session_preferences.content))
    error_message = "Session document content must reference the S3 log bucket name"
  }

  assert {
    condition     = can(regex("cloudWatchLogGroupName", aws_ssm_document.session_preferences.content))
    error_message = "Session document content must configure a CloudWatch log group"
  }

  assert {
    condition     = can(regex("kmsKeyId", aws_ssm_document.session_preferences.content))
    error_message = "Session document content must configure a KMS key"
  }

  assert {
    condition     = aws_ssm_association.inventory.name == "AWS-GatherSoftwareInventory"
    error_message = "Inventory association must use the AWS-managed GatherSoftwareInventory document"
  }
}

run "module_tags_applied" {
  command = plan

  variables {
    tags = { Owner = "test" }
  }

  assert {
    condition     = aws_ssm_document.session_preferences.tags["Owner"] == "test"
    error_message = "module-level tags must land on aws_ssm_document.session_preferences"
  }
}

# CMP-3: the module installs patches, not only defines a baseline.
run "patches_are_installed" {
  command = plan

  assert {
    condition     = toset(keys(aws_ssm_patch_baseline.this)) == toset(["AMAZON_LINUX_2023"]) && aws_ssm_default_patch_baseline.this["AMAZON_LINUX_2023"].operating_system == "AMAZON_LINUX_2023"
    error_message = "the default baseline must target Amazon Linux 2023 (Amazon Linux 2 support ended 2026-06-30)."
  }

  assert {
    condition     = aws_ssm_patch_baseline.this["AMAZON_LINUX_2023"].name == "org-patch-baseline-amazon-linux-2023"
    error_message = "a non-AL2 baseline name must carry the OS suffix."
  }

  assert {
    condition = (
      aws_ssm_association.patch_scan.name == "AWS-RunPatchBaseline" &&
      aws_ssm_association.patch_scan.parameters["Operation"] == "Scan" &&
      aws_ssm_association.patch_scan.schedule_expression == "rate(1 day)" &&
      one(aws_ssm_association.patch_scan.targets).key == "InstanceIds" &&
      one(aws_ssm_association.patch_scan.targets).values == tolist(["*"])
    )
    error_message = "a daily scan association must report patch compliance on every managed instance."
  }

  assert {
    condition = (
      aws_ssm_association.patch_install[0].name == "AWS-RunPatchBaseline" &&
      aws_ssm_association.patch_install[0].parameters["Operation"] == "Install" &&
      aws_ssm_association.patch_install[0].parameters["RebootOption"] == "RebootIfNeeded" &&
      aws_ssm_association.patch_install[0].schedule_expression == "cron(0 3 ? * SUN *)" &&
      aws_ssm_association.patch_install[0].max_concurrency == "10%" &&
      aws_ssm_association.patch_install[0].max_errors == "10%" &&
      aws_ssm_association.patch_install[0].compliance_severity == "CRITICAL"
    )
    error_message = "a weekly install association must apply approved patches (RebootIfNeeded, Sunday 03:00 UTC, 10% concurrency)."
  }

  assert {
    condition     = aws_ssm_association.patch_install[0].apply_only_at_cron_interval == true
    error_message = "the install association must not run (and reboot instances) at apply time: only on its cron schedule."
  }

  assert {
    condition = (
      one(aws_ssm_association.patch_install[0].targets).key == "InstanceIds" &&
      one(aws_ssm_association.patch_install[0].targets).values == tolist(["*"])
    )
    error_message = "with no patch_install_target_tag the install association targets every managed instance in the account and region."
  }
}

run "install_can_be_disabled" {
  command = plan

  variables {
    enable_patch_install = false
  }

  assert {
    condition     = length(aws_ssm_association.patch_install) == 0 && aws_ssm_association.patch_scan.parameters["Operation"] == "Scan"
    error_message = "disabling install must keep the scan."
  }
}

run "install_can_be_scoped_to_a_tag" {
  command = plan

  variables {
    patch_install_target_tag = { key = "PatchInstall", value = "true" }
  }

  assert {
    condition = (
      one(aws_ssm_association.patch_install[0].targets).key == "tag:PatchInstall" &&
      one(aws_ssm_association.patch_install[0].targets).values == tolist(["true"]) &&
      one(aws_ssm_association.patch_scan.targets).values == tolist(["*"])
    )
    error_message = "patch_install_target_tag must narrow the install association to tagged instances; the scan stays on every instance."
  }
}

run "several_operating_systems" {
  command = plan

  variables {
    patch_operating_systems = ["AMAZON_LINUX_2023", "WINDOWS"]
  }

  assert {
    condition     = toset(keys(aws_ssm_default_patch_baseline.this)) == toset(["AMAZON_LINUX_2023", "WINDOWS"])
    error_message = "every listed OS must get its own default baseline."
  }

  assert {
    condition = (
      toset([for f in aws_ssm_patch_baseline.this["WINDOWS"].approval_rule[0].patch_filter : f.key]) == toset(["PRODUCT", "CLASSIFICATION", "MSRC_SEVERITY"]) &&
      toset([for f in aws_ssm_patch_baseline.this["AMAZON_LINUX_2023"].approval_rule[0].patch_filter : f.key]) == toset(["PRODUCT", "CLASSIFICATION", "SEVERITY"])
    )
    error_message = "each baseline must use the patch filter keys its OS supports (Windows: CLASSIFICATION + MSRC_SEVERITY)."
  }
}

# Upgrade path: an Amazon Linux 2 estate keeps the old baseline name, so the
# moved block re-addresses the existing baseline instead of replacing it.
run "amazon_linux_2_keeps_the_old_baseline_name" {
  command = plan

  variables {
    patch_operating_systems = ["AMAZON_LINUX_2", "AMAZON_LINUX_2023"]
  }

  assert {
    condition     = aws_ssm_patch_baseline.this["AMAZON_LINUX_2"].name == "org-patch-baseline"
    error_message = "the AMAZON_LINUX_2 baseline must keep the pre-upgrade name (no replacement)."
  }
}

run "deprecated_single_os_input_still_works" {
  command = plan

  variables {
    patch_operating_system = "AMAZON_LINUX_2"
  }

  assert {
    condition     = toset(keys(aws_ssm_patch_baseline.this)) == toset(["AMAZON_LINUX_2"])
    error_message = "the deprecated patch_operating_system input must still select one baseline."
  }
}
