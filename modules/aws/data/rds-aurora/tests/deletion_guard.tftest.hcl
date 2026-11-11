# Deletion guard behaviour for the aws/data/rds-aurora module. Runs apply
# against mock_provider (no AWS credentials) so later runs plan against state.
#
# The guard carries prevent_destroy and replace_triggered_by on the cluster id,
# so a plan that REPLACES a protected cluster also plans to replace the guard
# and fails with "Instance cannot be destroyed". That failure is a plan error,
# not a checkable condition, so `terraform test` cannot expect it; the runs
# below cover the paths that must still succeed. To see the block, add
# `plan_options { replace = [aws_rds_cluster.this] }` to
# "protected_in_place_update_is_allowed": the run then fails on the guard.

mock_provider "aws" {}

variables {
  name               = "orders-db"
  kms_key_id         = "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  subnet_ids         = ["subnet-0aaa", "subnet-0bbb"]
  security_group_ids = ["sg-0aaa"]
}

run "protected_cluster_is_created_with_guard" {
  command = apply

  assert {
    condition     = length(terraform_data.deletion_guard) == 1
    error_message = "deletion_protection (default true) must create the guard."
  }

  assert {
    condition     = aws_rds_cluster.this.deletion_protection == true
    error_message = "the cluster's AWS-side deletion_protection must be set too."
  }
}

run "protected_in_place_update_is_allowed" {
  # Same state as above. An in-place change keeps the cluster id, so
  # replace_triggered_by does not fire and the guard must not block the plan.
  command = plan

  variables {
    backup_retention_period = 14
  }

  assert {
    condition     = aws_rds_cluster.this.backup_retention_period == 14
    error_message = "an in-place change on a protected cluster must plan."
  }
}

run "unprotected_cluster_is_created_without_guard" {
  state_key = "unprotected"
  command   = apply

  variables {
    deletion_protection = false
  }

  assert {
    condition     = length(terraform_data.deletion_guard) == 0
    error_message = "deletion_protection = false must not create the guard."
  }
}

run "unprotected_cluster_can_be_replaced" {
  state_key = "unprotected"
  command   = plan

  variables {
    deletion_protection = false
  }

  plan_options {
    replace = [aws_rds_cluster.this]
  }

  assert {
    condition     = aws_rds_cluster.this.deletion_protection == false
    error_message = "an unprotected cluster must plan a replacement without a guard error."
  }
}
