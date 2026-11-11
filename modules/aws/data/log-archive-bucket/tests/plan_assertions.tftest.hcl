# Resource-assertion tests for the aws/log-archive-bucket module.
#
# The bucket policy is built with jsonencode() in locals, so its JSON is real
# under mock_provider and the can(regex(...)) assertion below is meaningful.

mock_provider "aws" {}

variables {
  log_archive_bucket_name = "acme-org-log-archive"
  kms_key_arn             = "arn:aws:kms:eu-west-1:111122223333:key/abcd-1234"
  org_id                  = "o-abc123xyz0"
}

run "bucket_hardening_configured" {
  command = plan

  # All four Block Public Access dimensions must be enabled.
  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls == true &&
      aws_s3_bucket_public_access_block.this.block_public_policy == true &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls == true &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets == true
    )
    error_message = "All four Block Public Access booleans must be true"
  }

  assert {
    condition     = aws_s3_bucket.this.object_lock_enabled == true
    error_message = "Object Lock must be enabled at bucket creation"
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be Enabled"
  }

  assert {
    condition     = aws_s3_bucket_object_lock_configuration.this.rule[0].default_retention[0].mode == "COMPLIANCE"
    error_message = "Default Object Lock mode must be COMPLIANCE"
  }

  # aws:SourceOrgID scoping present in the bucket policy JSON.
  assert {
    condition     = can(regex("aws:SourceOrgID", aws_s3_bucket_policy.this.policy))
    error_message = "Bucket policy must scope log-delivery grants by aws:SourceOrgID"
  }

  # Non-TLS access is denied.
  assert {
    condition     = can(regex("aws:SecureTransport", aws_s3_bucket_policy.this.policy))
    error_message = "Bucket policy must deny non-TLS (aws:SecureTransport) access"
  }

  # Structural: every Allow log-delivery statement must itself carry the
  # SourceOrgID scope equal to var.org_id, not merely have the string appear
  # somewhere in the document. Catches a refactor that drops the condition from
  # one grant while keeping it on another.
  assert {
    condition = alltrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      try(s.Condition.StringEquals["aws:SourceOrgID"], null) == var.org_id
      if s.Effect == "Allow"
    ])
    error_message = "every Allow statement must be scoped by aws:SourceOrgID = var.org_id"
  }

  # Structural: a Deny statement must actually deny insecure transport.
  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Effect == "Deny" && try(s.Condition.Bool["aws:SecureTransport"], null) == "false"
    ])
    error_message = "policy must include a Deny statement conditioned on aws:SecureTransport = false"
  }
}

# Known-gaps A8: vended CloudWatch Logs delivery (flow / firewall / resolver
# logs) needs delivery.logs.amazonaws.com on the bucket, scoped to the org.
run "grants_vended_log_delivery" {
  command = plan

  assert {
    condition = length([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s
      if try(s.Principal.Service, "") == "delivery.logs.amazonaws.com" && try(s.Condition.StringEquals["aws:SourceOrgID"], "") == var.org_id
    ]) == 2
    error_message = "the log archive must grant delivery.logs.amazonaws.com AclCheck + Write, both scoped by aws:SourceOrgID."
  }
}

run "module_tags_applied" {
  command = plan

  variables {
    tags = { Owner = "test" }
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Owner"] == "test"
    error_message = "module-level tags must land on aws_s3_bucket.this"
  }
}

# S3 server access logs cannot land in an SSE-KMS / Object Lock bucket, so by
# default they go to a companion SSE-S3 bucket with no Object Lock.
run "access_logs_go_to_companion_sse_s3_bucket" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_logging.this.target_bucket == "acme-org-log-archive-access-logs" &&
      aws_s3_bucket_logging.this.target_bucket != var.log_archive_bucket_name &&
      output.access_log_bucket_name == "acme-org-log-archive-access-logs"
    )
    error_message = "access logs must target the companion <name>-access-logs bucket, never the archive itself"
  }

  assert {
    condition = (
      one(aws_s3_bucket_server_side_encryption_configuration.access_logs[0].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256" &&
      aws_s3_bucket_versioning.access_logs[0].versioning_configuration[0].status == "Enabled" &&
      aws_s3_bucket_public_access_block.access_logs[0].restrict_public_buckets == true &&
      aws_s3_bucket_ownership_controls.access_logs[0].rule[0].object_ownership == "BucketOwnerEnforced" &&
      aws_s3_bucket_lifecycle_configuration.access_logs[0].rule[0].expiration[0].days == 365
    )
    error_message = "the access-log bucket must use SSE-S3, no Object Lock, versioning, full public-access block, owner-enforced objects and its own expiry"
  }

  assert {
    condition = (
      one([for s in jsondecode(aws_s3_bucket_policy.access_logs[0].policy).Statement : s if s.Sid == "S3ServerAccessLogsWrite"]).Principal.Service == "logging.s3.amazonaws.com" &&
      one([for s in jsondecode(aws_s3_bucket_policy.access_logs[0].policy).Statement : s if s.Sid == "S3ServerAccessLogsWrite"]).Resource == "arn:aws:s3:::acme-org-log-archive-access-logs/s3-access-logs/*" &&
      one([for s in jsondecode(aws_s3_bucket_policy.access_logs[0].policy).Statement : s if s.Sid == "S3ServerAccessLogsWrite"]).Condition.ArnLike["aws:SourceArn"] == "arn:aws:s3:::acme-org-log-archive" &&
      one([for s in jsondecode(aws_s3_bucket_policy.access_logs[0].policy).Statement : s if s.Sid == "DenyInsecureTransport"]).Effect == "Deny"
    )
    error_message = "only the S3 logging service may write, only under the prefix, only for the log archive; non-TLS access is denied"
  }
}

run "existing_access_log_bucket_skips_companion" {
  command = plan

  variables {
    access_log_bucket = "acme-audit-access-logs"
  }

  assert {
    condition     = aws_s3_bucket_logging.this.target_bucket == "acme-audit-access-logs" && length(aws_s3_bucket.access_logs) == 0 && length(aws_s3_bucket_policy.access_logs) == 0
    error_message = "a supplied access_log_bucket must be the target and no companion bucket created"
  }
}

run "cloudtrail_grants_pinned_to_trail_owner_when_set" {
  command = plan

  variables {
    cloudtrail_trail_account_id = "111111111111"
  }

  assert {
    condition = alltrue([
      for sid in ["AWSCloudTrailAclCheck", "AWSCloudTrailWrite"] :
      one([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == sid]).Condition.ArnLike["aws:SourceArn"] == "arn:aws:cloudtrail:*:111111111111:trail/*" &&
      one([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == sid]).Condition.StringEquals["aws:SourceOrgID"] == var.org_id
    ])
    error_message = "CloudTrail grants must require both the org ID and a trail ARN in the trail owner account"
  }

  # Config is not a trail: its grant stays org-scoped only.
  assert {
    condition     = !can(one([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "AWSConfigWrite"]).Condition.ArnLike)
    error_message = "the Config grant must not carry the CloudTrail SourceArn pin"
  }
}

run "cloudtrail_grants_org_only_by_default" {
  command = plan

  assert {
    condition     = !can(one([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "AWSCloudTrailWrite"]).Condition.ArnLike)
    error_message = "with no cloudtrail_trail_account_id the CloudTrail grant must stay org-scoped only"
  }
}

run "deletion_guard_on_by_default" {
  command = plan

  assert {
    condition     = length(terraform_data.deletion_guard) == 1 && terraform_data.deletion_guard[0].input == var.log_archive_bucket_name
    error_message = "the log-archive bucket must carry a prevent_destroy guard by default"
  }
}

run "deletion_guard_can_be_disabled" {
  command = plan

  variables {
    enable_deletion_protection = false
  }

  assert {
    condition     = length(terraform_data.deletion_guard) == 0
    error_message = "enable_deletion_protection = false must omit the guard"
  }
}
