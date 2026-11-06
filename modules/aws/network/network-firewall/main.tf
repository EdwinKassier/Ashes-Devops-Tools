# AWS Network Firewall for the SRA landing zone inspection VPC.
#
# The whole module is gated behind var.enable_network_firewall (a COST toggle:
# a firewall endpoint per AZ bills hourly plus per-GB). When disabled, count = 0
# on every resource so nothing is created and the outputs degrade gracefully.
#
# Rule baseline (STRICT_ORDER engine — rule groups evaluate by priority, then
# the policy's stateful default actions apply to unmatched traffic):
#
#   priority 100+  AWS-managed threat rule groups (var.managed_rule_groups) —
#                  attack infrastructure, malware and botnet C2 domains. These
#                  drop known-bad traffic before any allow rule can pass it.
#   priority 1000  optional custom Suricata rules (var.suricata_rules).
#   priority 2000  optional egress domain allowlist (HTTP_HOST + TLS_SNI) —
#                  generated ALLOWLIST rules pass the listed domains and DROP all
#                  other HTTP/TLS flows from HOME_NET.
#   default        var.stateful_default_actions. Day-one default is
#                  ["aws:alert_established"]: unmatched traffic PASSES but is
#                  logged, so turning the firewall on never blackholes a running
#                  workload. Move to the AWS-recommended
#                  ["aws:drop_established", "aws:alert_established"] once the
#                  allow rules / allowlist cover legitimate egress.
#
# Stateless defaults forward everything to the stateful engine.
#
# Logging: ALERT and FLOW logs are both delivered to the log-archive bucket
# (separate prefixes). Delivery uses the delivery.logs.amazonaws.com principal,
# which the destination bucket policy (and its CMK) must authorize.
#
# Encryption at rest: when var.kms_key_arn is set, the rule groups, policy and
# firewall are encrypted with that customer-managed key (CUSTOMER_KMS). When it
# is empty, they fall back to AWS-owned keys and the CMK Checkov controls
# (CKV_AWS_345 / CKV_AWS_346) are skipped inline with justification.

# The region for the AWS-managed rule group ARNs comes from var.region, falling
# back to the provider's region only when it is not supplied.
data "aws_region" "current" {
  count = var.region == null ? 1 : 0
}

locals {
  use_cmk = trimspace(var.kms_key_arn) != ""

  create_custom_rules = var.enable_network_firewall && trimspace(var.suricata_rules) != ""
  create_allowlist    = var.enable_network_firewall && length(var.egress_domain_allowlist) > 0

  region = var.region != null ? var.region : data.aws_region.current[0].region

  managed_rule_group_arns = [
    for name in var.managed_rule_groups :
    "arn:${var.partition}:network-firewall:${local.region}:aws-managed:stateful-rulegroup/${name}"
  ]

  # Ordered references: managed threat groups first, then custom, then allowlist.
  stateful_references = concat(
    [for i, arn in local.managed_rule_group_arns : { arn = arn, priority = 100 + i }],
    local.create_custom_rules ? [{ arn = aws_networkfirewall_rule_group.stateful[0].arn, priority = 1000 }] : [],
    local.create_allowlist ? [{ arn = aws_networkfirewall_rule_group.domain_allowlist[0].arn, priority = 2000 }] : [],
  )
}

#checkov:skip=CKV_AWS_345:CMK encryption is opt-in via var.kms_key_arn (set by the network-hub stage that owns the KMS key); default falls back to an AWS-owned key.
resource "aws_networkfirewall_rule_group" "stateful" {
  count = local.create_custom_rules ? 1 : 0

  capacity = var.rule_group_capacity
  name     = var.rule_group_name
  type     = "STATEFUL"

  rule_group {
    rules_source {
      rules_string = var.suricata_rules
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  dynamic "encryption_configuration" {
    for_each = local.use_cmk ? [1] : []
    content {
      type   = "CUSTOMER_KMS"
      key_id = var.kms_key_arn
    }
  }

  tags = var.tags
}

#checkov:skip=CKV_AWS_345:CMK encryption is opt-in via var.kms_key_arn (set by the network-hub stage that owns the KMS key); default falls back to an AWS-owned key.
resource "aws_networkfirewall_rule_group" "domain_allowlist" {
  count = local.create_allowlist ? 1 : 0

  capacity = var.domain_allowlist_capacity
  name     = "${var.rule_group_name}-egress-allowlist"
  type     = "STATEFUL"

  rule_group {
    # HOME_NET comes from the policy-level variable (var.home_net_cidrs) so it
    # covers the spoke VPCs, not just the inspection VPC's own CIDR.
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["HTTP_HOST", "TLS_SNI"]
        targets              = var.egress_domain_allowlist
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  dynamic "encryption_configuration" {
    for_each = local.use_cmk ? [1] : []
    content {
      type   = "CUSTOMER_KMS"
      key_id = var.kms_key_arn
    }
  }

  tags = var.tags
}

#checkov:skip=CKV_AWS_346:CMK encryption is opt-in via var.kms_key_arn (set by the network-hub stage that owns the KMS key); default falls back to an AWS-owned key.
resource "aws_networkfirewall_firewall_policy" "this" {
  count = var.enable_network_firewall ? 1 : 0

  name = var.policy_name

  firewall_policy {
    # Send all stateless traffic (including fragments) to the stateful engine so
    # the stateful rules make the actual allow/drop decisions.
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    stateful_default_actions = var.stateful_default_actions

    dynamic "policy_variables" {
      for_each = length(var.home_net_cidrs) > 0 ? [1] : []
      content {
        rule_variables {
          key = "HOME_NET"
          ip_set {
            definition = var.home_net_cidrs
          }
        }
      }
    }

    dynamic "stateful_rule_group_reference" {
      for_each = local.stateful_references
      content {
        resource_arn = stateful_rule_group_reference.value.arn
        priority     = stateful_rule_group_reference.value.priority
      }
    }
  }

  dynamic "encryption_configuration" {
    for_each = local.use_cmk ? [1] : []
    content {
      type   = "CUSTOMER_KMS"
      key_id = var.kms_key_arn
    }
  }

  tags = var.tags
}

#checkov:skip=CKV_AWS_345:CMK encryption is opt-in via var.kms_key_arn (set by the network-hub stage that owns the KMS key); default falls back to an AWS-owned key.
resource "aws_networkfirewall_firewall" "this" {
  #checkov:skip=CKV2_AWS_63:Logging IS configured — aws_networkfirewall_logging_configuration.this delivers ALERT and FLOW logs to var.log_bucket_name for this firewall. Both resources are count-gated on enable_network_firewall and reference each other via [0] indexing, which Checkov's cross-resource graph check cannot resolve, so it reports the firewall as unlogged. False positive.
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

  tags = var.tags
}

resource "aws_networkfirewall_logging_configuration" "this" {
  count = var.enable_network_firewall ? 1 : 0

  firewall_arn = aws_networkfirewall_firewall.this[0].arn

  logging_configuration {
    # ALERT: every rule match with an alert/drop action (threat detections).
    log_destination_config {
      log_destination = {
        bucketName = var.log_bucket_name
        prefix     = "${var.log_prefix}/alert"
      }
      log_destination_type = "S3"
      log_type             = "ALERT"
    }

    # FLOW: network flow records for all traffic through the stateful engine.
    log_destination_config {
      log_destination = {
        bucketName = var.log_bucket_name
        prefix     = "${var.log_prefix}/flow"
      }
      log_destination_type = "S3"
      log_type             = "FLOW"
    }
  }
}
