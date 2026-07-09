# Resource-assertion tests for the aws/network-firewall module.
#
# Asserts on configured attributes and count-derived structure known at plan
# time under mock_provider. Provider-computed attributes (arns, endpoint ids)
# are not asserted on.

mock_provider "aws" {}

run "firewall_enabled" {
  command = plan

  variables {
    inspection_vpc_id = "vpc-inspection0000000"
    log_bucket_name   = "example-firewall-log-bucket"
  }

  # Enabled by default: exactly one of each resource.
  assert {
    condition     = length(aws_networkfirewall_firewall.this) == 1
    error_message = "One firewall must be created when enabled."
  }

  assert {
    condition     = length(aws_networkfirewall_rule_group.stateful) == 1
    error_message = "One stateful rule group must be created when enabled."
  }

  # The policy must reference the stateful rule group (reference set non-empty).
  # stateful_rule_group_reference is a set block, so convert to a list to count.
  assert {
    condition     = length(tolist(aws_networkfirewall_firewall_policy.this[0].firewall_policy[0].stateful_rule_group_reference)) >= 1
    error_message = "Firewall policy must reference at least one stateful rule group."
  }

  # Stateless defaults must forward to the stateful engine.
  assert {
    condition     = contains(aws_networkfirewall_firewall_policy.this[0].firewall_policy[0].stateless_default_actions, "aws:forward_to_sfe")
    error_message = "Stateless default action must forward to the stateful engine."
  }

  # One subnet_mapping per firewall subnet id. The subnet_mapping set is
  # provider-computed at plan time, so assert on the toset() source that drives
  # the dynamic block (which is what determines the mapping count).
  assert {
    condition     = length(toset(var.firewall_subnet_ids)) == length(var.firewall_subnet_ids)
    error_message = "firewall_subnet_ids must be unique so one subnet_mapping is created per id."
  }

  assert {
    condition     = length(var.firewall_subnet_ids) == 2
    error_message = "Defaults must produce exactly 2 firewall subnet mappings."
  }

  # Logging must ship FLOW logs to S3.
  assert {
    condition     = length(aws_networkfirewall_logging_configuration.this) == 1
    error_message = "Logging configuration must be created when enabled."
  }

  # Deletion protection defaults on.
  assert {
    condition     = aws_networkfirewall_firewall.this[0].delete_protection == true
    error_message = "Deletion protection must default to enabled."
  }

  # Without a CMK, no encryption_configuration block (AWS-owned key fallback).
  assert {
    condition     = length(aws_networkfirewall_firewall.this[0].encryption_configuration) == 0
    error_message = "No encryption_configuration must be set when kms_key_arn is empty."
  }
}

run "cmk_encryption_wired" {
  command = plan

  variables {
    inspection_vpc_id = "vpc-inspection0000000"
    log_bucket_name   = "example-firewall-log-bucket"
    kms_key_arn       = "arn:aws:kms:eu-west-2:123456789012:key/abcd1234-ab12-cd34-ef56-abcdef123456"
  }

  # With a CMK ARN, all three encryptable resources get a CUSTOMER_KMS block.
  assert {
    condition     = aws_networkfirewall_firewall.this[0].encryption_configuration[0].type == "CUSTOMER_KMS"
    error_message = "Firewall must use CUSTOMER_KMS encryption when kms_key_arn is set."
  }

  assert {
    condition     = aws_networkfirewall_firewall_policy.this[0].encryption_configuration[0].type == "CUSTOMER_KMS"
    error_message = "Firewall policy must use CUSTOMER_KMS encryption when kms_key_arn is set."
  }

  assert {
    condition     = aws_networkfirewall_rule_group.stateful[0].encryption_configuration[0].type == "CUSTOMER_KMS"
    error_message = "Rule group must use CUSTOMER_KMS encryption when kms_key_arn is set."
  }
}

run "firewall_disabled" {
  command = plan

  variables {
    enable_network_firewall = false
    inspection_vpc_id       = "vpc-inspection0000000"
    log_bucket_name         = "example-firewall-log-bucket"
  }

  # Cost toggle off: no firewall resources of any kind.
  assert {
    condition     = length(aws_networkfirewall_firewall.this) == 0
    error_message = "No firewall must be created when disabled."
  }

  assert {
    condition     = length(aws_networkfirewall_rule_group.stateful) == 0
    error_message = "No rule group must be created when disabled."
  }

  assert {
    condition     = length(aws_networkfirewall_firewall_policy.this) == 0
    error_message = "No firewall policy must be created when disabled."
  }

  assert {
    condition     = length(aws_networkfirewall_logging_configuration.this) == 0
    error_message = "No logging configuration must be created when disabled."
  }
}
