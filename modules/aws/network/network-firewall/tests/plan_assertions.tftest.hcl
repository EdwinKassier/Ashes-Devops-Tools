# Resource-assertion tests for the aws/network-firewall module.
#
# Asserts on configured attributes and count-derived structure known at plan
# time under mock_provider. Provider-computed attributes (arns, endpoint ids)
# are not asserted on.

mock_provider "aws" {}

variables {
  inspection_vpc_id = "vpc-inspection0000000"
  log_bucket_name   = "example-firewall-log-bucket"
  region            = "eu-west-2"
}

run "firewall_enabled" {
  command = plan

  assert {
    condition     = length(aws_networkfirewall_firewall.this) == 1 && length(aws_networkfirewall_firewall_policy.this) == 1
    error_message = "One firewall and one policy must be created when enabled."
  }

  # The placeholder drop-all-HTTP rule is gone: no custom group or allowlist by default.
  assert {
    condition     = length(aws_networkfirewall_rule_group.stateful) == 0 && length(aws_networkfirewall_rule_group.domain_allowlist) == 0
    error_message = "No custom Suricata or allowlist rule group must be created by default."
  }

  # STRICT_ORDER engine.
  assert {
    condition     = aws_networkfirewall_firewall_policy.this[0].firewall_policy[0].stateful_engine_options[0].rule_order == "STRICT_ORDER"
    error_message = "Firewall policy must use STRICT_ORDER rule evaluation."
  }

  # Safe day-one default: alert on unmatched established traffic, never drop.
  assert {
    condition     = toset(aws_networkfirewall_firewall_policy.this[0].firewall_policy[0].stateful_default_actions) == toset(["aws:alert_established"])
    error_message = "Default stateful action must be log-but-pass (aws:alert_established)."
  }

  # AWS-managed threat groups attached by ARN with ascending priority.
  assert {
    condition = toset([for r in aws_networkfirewall_firewall_policy.this[0].firewall_policy[0].stateful_rule_group_reference : r.resource_arn]) == toset([
      "arn:aws:network-firewall:eu-west-2:aws-managed:stateful-rulegroup/AttackInfrastructureStrictOrder",
      "arn:aws:network-firewall:eu-west-2:aws-managed:stateful-rulegroup/MalwareDomainsStrictOrder",
      "arn:aws:network-firewall:eu-west-2:aws-managed:stateful-rulegroup/BotNetCommandAndControlDomainsStrictOrder",
    ])
    error_message = "Policy must reference the default AWS-managed StrictOrder threat rule groups."
  }

  assert {
    condition     = output.stateful_rule_group_references[0].priority == 100 && output.stateful_rule_group_references[2].priority == 102
    error_message = "Managed rule groups must be ordered by priority starting at 100."
  }

  assert {
    condition     = contains(aws_networkfirewall_firewall_policy.this[0].firewall_policy[0].stateless_default_actions, "aws:forward_to_sfe")
    error_message = "Stateless default action must forward to the stateful engine."
  }

  # See network-hub: subnet_mapping is unknown under mock, so assert the input contract.
  assert {
    condition     = length(toset(var.firewall_subnet_ids)) == length(var.firewall_subnet_ids) && length(var.firewall_subnet_ids) == 2
    error_message = "firewall_subnet_ids must be unique (one subnet_mapping per id); defaults produce 2."
  }

  # Both ALERT and FLOW logs ship to the log bucket.
  assert {
    condition = toset([
      for c in aws_networkfirewall_logging_configuration.this[0].logging_configuration[0].log_destination_config : c.log_type
      if c.log_destination_type == "S3" && c.log_destination["bucketName"] == "example-firewall-log-bucket"
    ]) == toset(["ALERT", "FLOW"])
    error_message = "ALERT and FLOW logs must both be delivered to the log bucket."
  }

  assert {
    condition     = aws_networkfirewall_firewall.this[0].delete_protection == true
    error_message = "Deletion protection must default to enabled."
  }

  assert {
    condition     = length(aws_networkfirewall_firewall.this[0].encryption_configuration) == 0
    error_message = "No encryption_configuration must be set when kms_key_arn is empty."
  }
}

run "custom_rules_allowlist_and_drop_default" {
  command = plan

  variables {
    suricata_rules           = "pass tls $HOME_NET any -> $EXTERNAL_NET 443 (tls.sni; content:\"example.com\"; endswith; msg:\"allow example\"; flow:to_server; sid:100; rev:1;)"
    egress_domain_allowlist  = [".amazonaws.com", "github.com"]
    home_net_cidrs           = ["10.0.0.0/8"]
    stateful_default_actions = ["aws:drop_established", "aws:alert_established"]
  }

  override_resource {
    target          = aws_networkfirewall_rule_group.stateful[0]
    override_during = plan
    values          = { arn = "arn:aws:network-firewall:eu-west-2:123456789012:stateful-rulegroup/org-stateful" }
  }

  override_resource {
    target          = aws_networkfirewall_rule_group.domain_allowlist[0]
    override_during = plan
    values          = { arn = "arn:aws:network-firewall:eu-west-2:123456789012:stateful-rulegroup/org-stateful-egress-allowlist" }
  }

  assert {
    condition     = aws_networkfirewall_rule_group.stateful[0].rule_group[0].stateful_rule_options[0].rule_order == "STRICT_ORDER"
    error_message = "Custom rule group must use STRICT_ORDER to attach to a strict-order policy."
  }

  assert {
    condition = (
      aws_networkfirewall_rule_group.domain_allowlist[0].rule_group[0].rules_source[0].rules_source_list[0].generated_rules_type == "ALLOWLIST" &&
      toset(aws_networkfirewall_rule_group.domain_allowlist[0].rule_group[0].rules_source[0].rules_source_list[0].target_types) == toset(["HTTP_HOST", "TLS_SNI"]) &&
      toset(aws_networkfirewall_rule_group.domain_allowlist[0].rule_group[0].rules_source[0].rules_source_list[0].targets) == toset([".amazonaws.com", "github.com"])
    )
    error_message = "Allowlist must be an ALLOWLIST over HTTP_HOST and TLS_SNI with the supplied domains."
  }

  # Ordering: managed (100-102) < custom (1000) < allowlist (2000).
  assert {
    condition     = [for r in output.stateful_rule_group_references : r.priority] == [100, 101, 102, 1000, 2000]
    error_message = "Rule group priorities must place managed threat groups first, then custom rules, then the allowlist."
  }

  assert {
    condition     = output.stateful_rule_group_references[4].arn == "arn:aws:network-firewall:eu-west-2:123456789012:stateful-rulegroup/org-stateful-egress-allowlist"
    error_message = "The allowlist must be the lowest-priority (last) reference."
  }

  assert {
    condition     = toset(aws_networkfirewall_firewall_policy.this[0].firewall_policy[0].stateful_default_actions) == toset(["aws:drop_established", "aws:alert_established"])
    error_message = "The AWS-recommended drop_established + alert_established defaults must be configurable."
  }

  assert {
    condition     = one([for v in aws_networkfirewall_firewall_policy.this[0].firewall_policy[0].policy_variables[0].rule_variables : v.key]) == "HOME_NET"
    error_message = "home_net_cidrs must set the policy-level HOME_NET variable."
  }
}

run "cmk_encryption_wired" {
  command = plan

  variables {
    suricata_rules = "alert tcp $HOME_NET any -> $EXTERNAL_NET 23 (msg:\"telnet egress\"; sid:200; rev:1;)"
    kms_key_arn    = "arn:aws:kms:eu-west-2:123456789012:key/abcd1234-ab12-cd34-ef56-abcdef123456"
  }

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
    suricata_rules          = "alert tcp any any -> any 23 (msg:\"telnet\"; sid:300; rev:1;)"
    egress_domain_allowlist = ["github.com"]
  }

  assert {
    condition = (
      length(aws_networkfirewall_firewall.this) == 0 &&
      length(aws_networkfirewall_rule_group.stateful) == 0 &&
      length(aws_networkfirewall_rule_group.domain_allowlist) == 0 &&
      length(aws_networkfirewall_firewall_policy.this) == 0 &&
      length(aws_networkfirewall_logging_configuration.this) == 0
    )
    error_message = "No firewall resources of any kind must be created when disabled."
  }
}

run "module_tags_applied" {
  command = plan

  variables {
    tags = { Owner = "test" }
  }

  assert {
    condition     = aws_networkfirewall_firewall.this[0].tags["Owner"] == "test"
    error_message = "module-level tags must land on aws_networkfirewall_firewall.this"
  }
}
