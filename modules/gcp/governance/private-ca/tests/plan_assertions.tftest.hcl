# Plan-time wiring assertions for the private-ca module.
# mock_provider means computed values (id, state) are unknown, so we assert
# only config-derived, plan-knowable attributes.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  ca_pool_name = "test-pool"
  name         = "test-ca"
}

run "root_ca_defaults_wire_through" {
  command = plan

  # CA pool tier default is ENTERPRISE.
  assert {
    condition     = google_privateca_ca_pool.this.tier == "ENTERPRISE"
    error_message = "CA pool tier should default to ENTERPRISE."
  }

  # ROOT ca_type maps to the CAS SELF_SIGNED resource type.
  assert {
    condition     = google_privateca_certificate_authority.this[0].type == "SELF_SIGNED"
    error_message = "ROOT ca_type should map to SELF_SIGNED."
  }

  # deletion_protection defaults to true.
  assert {
    condition     = google_privateca_certificate_authority.this[0].deletion_protection == true
    error_message = "deletion_protection should default to true."
  }

  # CAS-specific toggles default to their safe values.
  assert {
    condition     = google_privateca_certificate_authority.this[0].ignore_active_certificates_on_deletion == false
    error_message = "ignore_active_certificates_on_deletion should default to false."
  }

  assert {
    condition     = google_privateca_certificate_authority.this[0].skip_grace_period == false
    error_message = "skip_grace_period should default to false."
  }
}

run "subordinate_type_propagates" {
  command = plan

  variables {
    ca_type = "SUBORDINATE"
  }

  assert {
    condition     = google_privateca_certificate_authority.this[0].type == "SUBORDINATE"
    error_message = "SUBORDINATE ca_type should map to the SUBORDINATE resource type."
  }
}

run "devops_tier_and_labels_wire_through" {
  command = plan

  variables {
    tier   = "DEVOPS"
    labels = { team = "platform" }
  }

  assert {
    condition     = google_privateca_ca_pool.this.tier == "DEVOPS"
    error_message = "CA pool tier should reflect the DEVOPS input."
  }

  assert {
    condition     = google_privateca_ca_pool.this.labels["team"] == "platform"
    error_message = "CA pool labels should propagate from var.labels."
  }
}

run "disabling_ca_creates_pool_only" {
  command = plan

  variables {
    enable_ca = false
  }

  assert {
    condition     = length(google_privateca_certificate_authority.this) == 0
    error_message = "enable_ca=false should create no certificate authority."
  }
}
