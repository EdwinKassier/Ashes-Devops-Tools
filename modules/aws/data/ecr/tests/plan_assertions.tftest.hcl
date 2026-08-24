# Plan assertions for the data/ecr module (mock_provider — no creds).

mock_provider "aws" {}

run "repo_secure_defaults" {
  command = plan

  variables {
    repositories = {
      "platform/api" = {}
    }
  }

  assert {
    condition     = aws_ecr_repository.this["platform/api"].image_tag_mutability == "IMMUTABLE"
    error_message = "Repositories must default to IMMUTABLE tags"
  }

  assert {
    condition     = aws_ecr_repository.this["platform/api"].image_scanning_configuration[0].scan_on_push == true
    error_message = "scan_on_push must default to true"
  }

  assert {
    condition     = aws_ecr_repository.this["platform/api"].encryption_configuration[0].encryption_type == "AES256"
    error_message = "Encryption must default to AES256 when no KMS key is supplied"
  }
}

run "kms_and_lifecycle_and_org_policy" {
  command = plan

  variables {
    org_id = "o-abc1234567"
    repositories = {
      "platform/api" = {
        kms_key_arn                = "arn:aws:kms:eu-west-2:111122223333:key/abcd-1234"
        expire_untagged_after_days = 14
      }
    }
  }

  assert {
    condition     = aws_ecr_repository.this["platform/api"].encryption_configuration[0].encryption_type == "KMS"
    error_message = "Encryption must be KMS when a kms_key_arn is supplied"
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 1
    error_message = "A lifecycle policy must be created when expiry rules are given"
  }

  assert {
    condition     = length(aws_ecr_repository_policy.org) == 1
    error_message = "An org-scoped repository policy must be created when org_id is set"
  }
}

run "no_lifecycle_or_org_policy_by_default" {
  command = plan

  variables {
    repositories = {
      "platform/api" = {}
    }
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 0
    error_message = "No lifecycle policy without expiry rules"
  }

  assert {
    condition     = length(aws_ecr_repository_policy.org) == 0
    error_message = "No org repository policy when org_id is null"
  }
}
