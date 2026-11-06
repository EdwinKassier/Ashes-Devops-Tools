# REAL-APPLY suite: no mock_provider. Applies into a disposable sandbox account
# and asserts on values read back from the live AWS APIs. `terraform test`
# destroys every resource it created when the file finishes (pass or fail);
# the sandbox-e2e workflow adds a tag-scoped safety-net cleanup on top.
#
# Inputs come from TF_VAR_region / TF_VAR_run_id / TF_VAR_run_attempt.
# Run via `make e2e-aws` or .github/workflows/sandbox-e2e.yml.
# Never run this against a landing-zone account.

run "apply_aws_primitives" {
  command = apply

  # --- KMS + log-archive bucket ---------------------------------------------

  assert {
    condition     = data.aws_kms_key.archive.enabled && data.aws_kms_key.archive.key_state == "Enabled" && data.aws_kms_key.archive.key_manager == "CUSTOMER"
    error_message = "CMK read back from KMS is not an enabled customer-managed key."
  }

  assert {
    condition     = data.aws_s3_object.canary.server_side_encryption == "aws:kms"
    error_message = "Canary object was not encrypted with SSE-KMS by the bucket's default encryption."
  }

  assert {
    condition     = data.aws_s3_object.canary.sse_kms_key_id == module.kms.key_arn
    error_message = "Canary object was encrypted with a key other than the CMK from modules/aws/data/kms-key."
  }

  assert {
    condition     = data.aws_s3_object.canary.bucket_key_enabled
    error_message = "S3 Bucket Key is not enabled for SSE-KMS (module sets bucket_key_enabled = true)."
  }

  assert {
    condition     = data.aws_s3_object.canary.object_lock_mode == "GOVERNANCE" && data.aws_s3_object.canary.object_lock_retain_until_date != ""
    error_message = "Canary object did not inherit the bucket's default Object Lock retention."
  }

  # --- Network ---------------------------------------------------------------

  assert {
    condition     = data.aws_vpc.this.cidr_block == "10.250.0.0/16"
    error_message = "VPC CIDR read back from EC2 does not match the requested block."
  }

  assert {
    condition     = data.aws_vpc.this.enable_dns_support && data.aws_vpc.this.enable_dns_hostnames
    error_message = "VPC DNS support/hostnames are not enabled."
  }

  assert {
    condition     = data.aws_subnet.private.cidr_block == "10.250.0.0/24" && !data.aws_subnet.private.map_public_ip_on_launch
    error_message = "Private subnet CIDR is wrong or it auto-assigns public IPs."
  }

  assert {
    condition     = length(module.vpc.subnet_ids_by_tier["private"]) == 1
    error_message = "az_count = 1 must yield exactly one private subnet."
  }

  assert {
    condition     = data.aws_vpc_endpoint.s3.state == "available" && length(data.aws_vpc_endpoint.s3.route_table_ids) == 1
    error_message = "S3 gateway endpoint is not available or not associated with the private route table."
  }

  # --- Tagging: provider default_tags reach module resources -----------------

  assert {
    condition     = lookup(data.aws_vpc.this.tags, "e2e-run-id", "") == var.run_id && lookup(data.aws_subnet.private.tags, "e2e-run-id", "") == var.run_id
    error_message = "Provider default_tags did not propagate to module-created resources."
  }
}
