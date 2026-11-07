# Plan assertions for the tiered-vpc firewall_mode switch: legacy (tag-based
# VPC rules, default), both (VPC rules plus a network firewall policy keyed on
# tier subnet CIDRs) and policy (network firewall policy only).

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id = "mock-project"
  name       = "mock-vpc"
  region     = "europe-west1"
  cidr_block = "10.0.0.0/16"
  zones      = ["europe-west1-b", "europe-west1-c"]
}

run "legacy_mode_rule_addresses_present" {
  command = plan

  assert {
    condition = alltrue([
      length(module.firewall_apigateway_to_public) == 1,
      length(module.firewall_public_to_compute) == 1,
      length(module.firewall_compute_to_database) == 1,
      length(module.firewall_iap_ssh_rdp) == 1,
      length(module.firewall_health_checks) == 1,
      length(module.firewall_database_deny_egress) == 1,
      length(module.firewall_deny_all) == 1,
    ])
    error_message = "The default (legacy) mode must keep all 7 tag-based VPC rule module calls, one instance each at [0]."
  }

  assert {
    condition     = module.firewall_deny_all[0].name == "mock-vpc-deny-all-ingress" && module.firewall_compute_to_database[0].name == "mock-vpc-allow-compute-db"
    error_message = "Legacy rule names must be unchanged."
  }

  assert {
    condition     = length(google_compute_network_firewall_policy.tier) == 0 && length(google_compute_network_firewall_policy_association.tier) == 0 && length(google_compute_network_firewall_policy_rule.tier) == 0
    error_message = "Legacy mode must not plan a network firewall policy, association or policy rules."
  }

  assert {
    condition     = module.vpc.network.network_firewall_policy_enforcement_order == null
    error_message = "Legacy mode must leave the network's enforcement order unset (unchanged plan)."
  }

  assert {
    condition     = output.firewall_policy_id == null && output.firewall_policy_name == null
    error_message = "Legacy mode exposes no firewall policy."
  }
}

run "both_mode_one_policy_one_association" {
  command = plan

  variables {
    firewall_mode = "both"
  }

  assert {
    condition     = length(google_compute_network_firewall_policy.tier) == 1 && length(google_compute_network_firewall_policy_association.tier) == 1
    error_message = "Both mode must plan exactly one network firewall policy and one association (a VPC takes only one global policy)."
  }

  assert {
    condition     = google_compute_network_firewall_policy.tier[0].name == "mock-vpc-tier-policy"
    error_message = "The policy must be named <name>-tier-policy."
  }

  assert {
    condition     = length(module.firewall_deny_all) == 1 && length(module.firewall_public_to_compute) == 1
    error_message = "Both mode must keep the legacy VPC rules while the policy is added."
  }

  assert {
    condition     = module.vpc.network.network_firewall_policy_enforcement_order == null
    error_message = "Both mode must keep the default AFTER_CLASSIC_FIREWALL order so legacy rules are evaluated first."
  }

  assert {
    condition     = length(distinct([for r in google_compute_network_firewall_policy_rule.tier : r.priority])) == length(google_compute_network_firewall_policy_rule.tier)
    error_message = "Policy rule priorities must be unique within the policy."
  }
}

run "db_tier_source_is_compute_subnet_ranges" {
  command = plan

  variables {
    firewall_mode = "both"
  }

  assert {
    condition     = toset(google_compute_network_firewall_policy_rule.tier["compute-to-database"].match[0].src_ip_ranges) == toset(["10.0.16.0/24", "10.0.17.0/24"])
    error_message = "The database tier rule must take the compute (private) subnet CIDRs as its source, not a network tag."
  }

  assert {
    condition     = toset(google_compute_network_firewall_policy_rule.tier["compute-to-database"].match[0].dest_ip_ranges) == toset(["10.0.32.0/24", "10.0.33.0/24"])
    error_message = "The database tier rule must target the database subnet CIDRs."
  }

  assert {
    condition     = toset(google_compute_network_firewall_policy_rule.tier["compute-to-database"].match[0].layer4_configs[0].ports) == toset(["3306", "5432", "6379"])
    error_message = "The database tier rule must open firewall.database_ports."
  }

  assert {
    condition = alltrue([
      for r in google_compute_network_firewall_policy_rule.tier :
      r.target_service_accounts == null || r.direction == "EGRESS"
    ])
    error_message = "target_service_accounts may be used only on egress policy rules."
  }

  assert {
    condition     = toset(google_compute_network_firewall_policy_rule.tier["health-checks"].match[0].src_ip_ranges) == toset(["35.191.0.0/16", "130.211.0.0/22"])
    error_message = "The health-check probe ranges must become a policy rule."
  }
}

run "policy_mode_no_vpc_rules" {
  command = plan

  variables {
    firewall_mode = "policy"
  }

  # Implicit enforcement order in policy mode raises the flip warning.
  expect_failures = [check.firewall_policy_enforcement_order_explicit]

  assert {
    condition = alltrue([
      length(module.firewall_apigateway_to_public) == 0,
      length(module.firewall_public_to_compute) == 0,
      length(module.firewall_compute_to_database) == 0,
      length(module.firewall_iap_ssh_rdp) == 0,
      length(module.firewall_health_checks) == 0,
      length(module.firewall_database_deny_egress) == 0,
      length(module.firewall_deny_all) == 0,
    ])
    error_message = "Policy mode must plan no tag-based VPC rules."
  }

  assert {
    condition     = length(google_compute_network_firewall_policy.tier) == 1 && length(google_compute_network_firewall_policy_association.tier) == 1
    error_message = "Policy mode must plan the network firewall policy and its association."
  }

  assert {
    condition     = module.vpc.network.network_firewall_policy_enforcement_order == "BEFORE_CLASSIC_FIREWALL"
    error_message = "Policy mode must default the enforcement order to BEFORE_CLASSIC_FIREWALL."
  }
}

run "policy_mode_enforcement_order_override" {
  command = plan

  variables {
    firewall_mode                     = "policy"
    firewall_policy_enforcement_order = "AFTER_CLASSIC_FIREWALL"
  }

  assert {
    condition     = module.vpc.network.network_firewall_policy_enforcement_order == "AFTER_CLASSIC_FIREWALL"
    error_message = "An explicit enforcement order must win, so the order can flip as a separate in-place step."
  }
}

run "no_trailing_deny_all" {
  command = plan

  variables {
    firewall_mode                     = "policy"
    firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
    firewall = {
      api_gateway_source_ranges = ["10.10.0.0/24"]
    }
  }

  assert {
    condition = alltrue([
      for r in google_compute_network_firewall_policy_rule.tier :
      !(r.direction == "INGRESS" && r.action == "deny")
    ])
    error_message = "The policy must have no ingress deny (no trailing deny-all): unmatched traffic falls through so GKE's automatic VPC rules keep working."
  }

  assert {
    condition     = google_compute_network_firewall_policy_rule.tier["database-deny-egress"].action == "deny" && google_compute_network_firewall_policy_rule.tier["database-deny-egress"].direction == "EGRESS" && toset(google_compute_network_firewall_policy_rule.tier["database-deny-egress"].match[0].src_ip_ranges) == toset(["10.0.32.0/24", "10.0.33.0/24"])
    error_message = "The database-tier egress deny must be kept, sourced on the database subnet CIDRs."
  }

  assert {
    condition     = toset(google_compute_network_firewall_policy_rule.tier["apigateway-to-public"].match[0].src_ip_ranges) == toset(["10.10.0.0/24"]) && toset(google_compute_network_firewall_policy_rule.tier["apigateway-to-public"].match[0].dest_ip_ranges) == toset(["10.0.0.0/24", "10.0.1.0/24"])
    error_message = "The API gateway rule must use firewall.api_gateway_source_ranges and target the public subnet CIDRs."
  }
}

run "policy_mode_without_apigw_ranges_or_iap" {
  command = plan

  variables {
    firewall_mode                     = "policy"
    firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
    firewall = {
      enable_iap_access = false
    }
  }

  assert {
    condition     = !contains(keys(google_compute_network_firewall_policy_rule.tier), "apigateway-to-public") && !contains(keys(google_compute_network_firewall_policy_rule.tier), "iap-ssh-rdp")
    error_message = "The API gateway rule needs explicit source ranges and the IAP rule follows firewall.enable_iap_access."
  }
}

run "explicit_enforcement_order_silences_flip_warning" {
  command = plan

  variables {
    firewall_mode                     = "policy"
    firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
  }

  # No expect_failures: the check must pass once the order is explicit.
  assert {
    condition     = module.vpc.network.network_firewall_policy_enforcement_order == "BEFORE_CLASSIC_FIREWALL"
    error_message = "An explicit BEFORE_CLASSIC_FIREWALL must reach the network."
  }
}
