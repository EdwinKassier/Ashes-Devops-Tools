# Variable validation tests for the aws/systems-manager module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "defaults_accepted" {
  # Accept case: required inputs set, everything else on defaults.
  command = plan

  variables {
    log_bucket_name = "org-ssm-session-logs"
    kms_key_id      = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
  }
}

run "bad_operating_system_rejected" {
  # Reject case: an unsupported OS must trip the allowed-set validation.
  command = plan

  variables {
    log_bucket_name        = "org-ssm-session-logs"
    kms_key_id             = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    patch_operating_system = "SOLARIS"
  }

  expect_failures = [var.patch_operating_system]
}

run "rejects_unknown_reboot_option" {
  command = plan

  variables {
    log_bucket_name     = "org-ssm-session-logs"
    kms_key_id          = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    patch_reboot_option = "Always"
  }

  expect_failures = [var.patch_reboot_option]
}

run "rejects_unsupported_patch_os" {
  # Only OS families whose approval-rule filters the module models are accepted.
  command = plan

  variables {
    log_bucket_name         = "org-ssm-session-logs"
    kms_key_id              = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    patch_operating_systems = ["AMAZON_LINUX_2023", "UBUNTU"]
  }

  expect_failures = [var.patch_operating_systems]
}

run "rejects_rate_install_schedule" {
  # apply_only_at_cron_interval needs a cron expression.
  command = plan

  variables {
    log_bucket_name        = "org-ssm-session-logs"
    kms_key_id             = "arn:aws:kms:us-east-1:111111111111:key/abcd-1234"
    patch_install_schedule = "rate(7 days)"
  }

  expect_failures = [var.patch_install_schedule]
}
