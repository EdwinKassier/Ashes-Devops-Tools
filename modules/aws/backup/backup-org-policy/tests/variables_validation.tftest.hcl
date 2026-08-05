# Variable validation tests for the aws/backup-org-policy module.
# All runs use mock_provider so no AWS credentials are required.

mock_provider "aws" {}

run "ou_target_accepted" {
  # A well-formed OU id must pass the target_ou_id validation.
  command = plan

  variables {
    backup_role_arn = "arn:aws:iam::123456789012:role/OrgBackupRole"
    target_ou_id    = "ou-abcd-1example"
  }
}

run "root_target_accepted" {
  # The org root id shape must also pass.
  command = plan

  variables {
    backup_role_arn = "arn:aws:iam::123456789012:role/OrgBackupRole"
    target_ou_id    = "r-abcd"
  }
}

run "bad_target_ou_id_rejected" {
  # A value that is neither an OU nor a root id must be rejected.
  command = plan

  variables {
    backup_role_arn = "arn:aws:iam::123456789012:role/OrgBackupRole"
    target_ou_id    = "not-an-ou"
  }

  expect_failures = [var.target_ou_id]
}
