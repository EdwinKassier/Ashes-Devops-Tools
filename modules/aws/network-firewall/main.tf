# AWS Network Firewall for the SRA landing zone inspection VPC.
#
# The whole module is gated behind var.enable_network_firewall (a COST toggle:
# a firewall endpoint per AZ bills hourly plus per-GB). When disabled, count = 0
# on every resource so nothing is created and the outputs degrade gracefully.
#
# Topology: a STATEFUL Suricata rule group is referenced by a firewall policy
# whose stateless defaults forward everything to the stateful engine
# (aws:forward_to_sfe). The firewall itself lands in the inspection VPC with one
# subnet mapping per firewall subnet, and flow logs are delivered to S3.
#
# Encryption at rest: when var.kms_key_arn is set, the rule group, policy, and
# firewall are encrypted with that customer-managed key (CUSTOMER_KMS). When it
# is empty, they fall back to AWS-owned keys and the CMK Checkov controls
# (CKV_AWS_345 / CKV_AWS_346) are skipped inline with justification — the CMK is
# composed by the network-hub stage (which owns the KMS key), not this leaf.

locals {
  use_cmk = trimspace(var.kms_key_arn) != ""
}

#checkov:skip=CKV_AWS_345:CMK encryption is opt-in via var.kms_key_arn (set by the network-hub stage that owns the KMS key); default falls back to an AWS-owned key.
resource "aws_networkfirewall_rule_group" "stateful" {
  count = var.enable_network_firewall ? 1 : 0

  capacity = var.rule_group_capacity
  name     = var.rule_group_name
  type     = "STATEFUL"

  rule_group {
    rules_source {
      rules_string = var.suricata_rules
    }
  }

  dynamic "encryption_configuration" {
    for_each = local.use_cmk ? [1] : []
    content {
      type   = "CUSTOMER_KMS"
      key_id = var.kms_key_arn
    }
  }
}

#checkov:skip=CKV_AWS_346:CMK encryption is opt-in via var.kms_key_arn (set by the network-hub stage that owns the KMS key); default falls back to an AWS-owned key.
resource "aws_networkfirewall_firewall_policy" "this" {
  count = var.enable_network_firewall ? 1 : 0

  name = var.policy_name

  firewall_policy {
    # Send all stateless traffic (including fragments) to the stateful engine so
    # the Suricata rules make the actual allow/drop decisions.
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateful[0].arn
    }
  }

  dynamic "encryption_configuration" {
    for_each = local.use_cmk ? [1] : []
    content {
      type   = "CUSTOMER_KMS"
      key_id = var.kms_key_arn
    }
  }
}

#checkov:skip=CKV_AWS_345:CMK encryption is opt-in via var.kms_key_arn (set by the network-hub stage that owns the KMS key); default falls back to an AWS-owned key.
resource "aws_networkfirewall_firewall" "this" {
  #checkov:skip=CKV2_AWS_63:Logging IS configured — aws_networkfirewall_logging_configuration.this delivers FLOW logs to var.log_bucket_name for this firewall. Both resources are count-gated on enable_network_firewall and reference each other via [0] indexing, which Checkov's cross-resource graph check cannot resolve, so it reports the firewall as unlogged. False positive.
  count = var.enable_network_firewall ? 1 : 0

  name                = var.firewall_name
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this[0].arn
  vpc_id              = var.inspection_vpc_id

  # Deletion protection on by default (CKV_AWS_344): a landing-zone inspection
  # firewall should not be torn down accidentally. Toggle off for teardown.
  delete_protection = var.delete_protection

  dynamic "subnet_mapping" {
    for_each = toset(var.firewall_subnet_ids)
    content {
      subnet_id = subnet_mapping.value
    }
  }

  dynamic "encryption_configuration" {
    for_each = local.use_cmk ? [1] : []
    content {
      type   = "CUSTOMER_KMS"
      key_id = var.kms_key_arn
    }
  }
}

resource "aws_networkfirewall_logging_configuration" "this" {
  count = var.enable_network_firewall ? 1 : 0

  firewall_arn = aws_networkfirewall_firewall.this[0].arn

  logging_configuration {
    log_destination_config {
      log_destination = {
        bucketName = var.log_bucket_name
      }
      log_destination_type = "S3"
      log_type             = "FLOW"
    }
  }
}
