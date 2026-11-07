# Plan assertions for internal-lb firewall_mode: the proxy-only subnet allow
# rule as a tag-targeted VPC rule (legacy, default), as a rule in the VPC's
# network firewall policy (policy), or both during migration.

mock_provider "google" {}

variables {
  project_id               = "mock-project"
  name                     = "test-lb"
  region                   = "europe-west1"
  network                  = "projects/mock-project/global/networks/mock-vpc"
  subnet                   = "projects/mock-project/regions/europe-west1/subnetworks/mock-subnet"
  is_l7                    = false
  proxy_only_subnet_ranges = ["10.129.0.0/23"]
  backend_target_tags      = ["compute"]
  backends = [
    {
      group = "projects/mock-project/zones/europe-west1-b/instanceGroups/mock-ig"
    }
  ]
}

run "legacy_mode_vpc_rule_only" {
  command = plan

  assert {
    condition     = length(google_compute_firewall.allow_proxy) == 1 && length(google_compute_network_firewall_policy_rule.allow_proxy) == 0
    error_message = "The default (legacy) mode must keep only the VPC firewall rule."
  }
}

run "both_mode_vpc_and_policy_rule" {
  command = plan

  variables {
    firewall_mode   = "both"
    firewall_policy = "mock-vpc-tier-policy"
  }

  assert {
    condition     = length(google_compute_firewall.allow_proxy) == 1 && length(google_compute_network_firewall_policy_rule.allow_proxy) == 1
    error_message = "Both mode must plan the VPC rule and the policy rule."
  }

  assert {
    condition     = google_compute_network_firewall_policy_rule.allow_proxy[0].firewall_policy == "mock-vpc-tier-policy" && toset(google_compute_network_firewall_policy_rule.allow_proxy[0].match[0].src_ip_ranges) == toset(["10.129.0.0/23"]) && toset(google_compute_network_firewall_policy_rule.allow_proxy[0].match[0].layer4_configs[0].ports) == toset(["80"])
    error_message = "The policy rule must admit the proxy-only ranges on backend_port in the given policy."
  }
}

run "policy_mode_policy_rule_only" {
  command = plan

  variables {
    firewall_mode   = "policy"
    firewall_policy = "mock-vpc-tier-policy"
  }

  assert {
    condition     = length(google_compute_firewall.allow_proxy) == 0 && length(google_compute_network_firewall_policy_rule.allow_proxy) == 1
    error_message = "Policy mode must plan only the policy rule."
  }

  assert {
    condition     = google_compute_network_firewall_policy_rule.allow_proxy[0].target_service_accounts == null && google_compute_network_firewall_policy_rule.allow_proxy[0].direction == "INGRESS"
    error_message = "The ingress policy rule must not use target_service_accounts."
  }
}

run "policy_mode_requires_policy_name" {
  command = plan

  variables {
    firewall_mode = "policy"
  }

  expect_failures = [google_compute_network_firewall_policy_rule.allow_proxy]
}

run "policy_mode_rejects_reserved_priority" {
  command = plan

  variables {
    firewall_mode                 = "policy"
    firewall_policy               = "mock-vpc-tier-policy"
    firewall_policy_rule_priority = 64010
  }

  expect_failures = [google_compute_network_firewall_policy_rule.allow_proxy]
}

run "rejects_invalid_firewall_mode" {
  command = plan

  variables {
    firewall_mode = "tags"
  }

  expect_failures = [var.firewall_mode]
}

run "policy_rule_priority_lb_a" {
  command = plan

  variables {
    name            = "orders-ilb"
    firewall_mode   = "policy"
    firewall_policy = "mock-vpc-tier-policy"
  }

  assert {
    condition     = output.firewall_policy_rule_priority >= 1000 && output.firewall_policy_rule_priority <= 63999 && google_compute_network_firewall_policy_rule.allow_proxy[0].priority == output.firewall_policy_rule_priority
    error_message = "The derived policy rule priority must lie in 1000-63999, outside the reserved tiered-vpc block."
  }
}

run "policy_rule_priority_lb_b_distinct" {
  command = plan

  variables {
    name            = "payments-ilb"
    firewall_mode   = "policy"
    firewall_policy = "mock-vpc-tier-policy"
  }

  assert {
    condition     = output.firewall_policy_rule_priority != run.policy_rule_priority_lb_a.firewall_policy_rule_priority
    error_message = "Two ILBs with distinct names on one VPC policy must derive distinct policy rule priorities (both used to default to 1000)."
  }

  assert {
    condition     = google_compute_firewall.allow_proxy == [] && output.firewall_policy_rule_priority != var.firewall_priority
    error_message = "The policy rule priority must not fall back to the shared firewall_priority default."
  }
}

run "policy_rule_priority_explicit_wins" {
  command = plan

  variables {
    firewall_mode                 = "both"
    firewall_policy               = "mock-vpc-tier-policy"
    firewall_policy_rule_priority = 2500
  }

  assert {
    condition     = google_compute_network_firewall_policy_rule.allow_proxy[0].priority == 2500 && google_compute_firewall.allow_proxy[0].priority == 1000
    error_message = "An explicit firewall_policy_rule_priority must win for the policy rule; the VPC rule keeps firewall_priority."
  }
}

run "legacy_mode_no_policy_priority" {
  command = plan

  assert {
    condition     = output.firewall_policy_rule_priority == null
    error_message = "Legacy mode exposes no policy rule priority."
  }
}
