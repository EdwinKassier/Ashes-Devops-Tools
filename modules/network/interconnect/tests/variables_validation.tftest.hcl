# Variable validation tests for the network/interconnect module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id      = "mock-project"
  region          = "us-central1"
  network         = "projects/mock-project/global/networks/mock-vpc"
  attachment_name = "test-attachment"
  router_name     = "test-router"
}

# ── attachment_name ────────────────────────────────────────────────────────────

run "accepts_valid_attachment_name" {
  command = plan

  variables {
    attachment_name = "my-attachment-01"
  }
}

run "rejects_attachment_name_starting_with_number" {
  command = plan

  expect_failures = [var.attachment_name]

  variables {
    attachment_name = "1invalid"
  }
}

run "rejects_attachment_name_with_uppercase" {
  command = plan

  expect_failures = [var.attachment_name]

  variables {
    attachment_name = "MyAttachment"
  }
}

# ── interconnect_type ──────────────────────────────────────────────────────────

run "accepts_partner_interconnect_type" {
  command = plan

  variables {
    interconnect_type = "PARTNER"
  }
}

run "accepts_dedicated_interconnect_type" {
  command = plan

  variables {
    interconnect_type = "DEDICATED"
  }
}

run "rejects_invalid_interconnect_type" {
  command = plan

  expect_failures = [var.interconnect_type]

  variables {
    interconnect_type = "SHARED"
  }
}

# ── vlan_tag ───────────────────────────────────────────────────────────────────

run "accepts_null_vlan_tag" {
  command = plan

  variables {
    vlan_tag = null
  }
}

run "accepts_valid_vlan_tag" {
  command = plan

  variables {
    vlan_tag = 100
  }
}

run "accepts_boundary_vlan_tag_1" {
  command = plan

  variables {
    vlan_tag = 1
  }
}

run "accepts_boundary_vlan_tag_4094" {
  command = plan

  variables {
    vlan_tag = 4094
  }
}

run "rejects_vlan_tag_zero" {
  command = plan

  expect_failures = [var.vlan_tag]

  variables {
    vlan_tag = 0
  }
}

run "rejects_vlan_tag_above_4094" {
  command = plan

  expect_failures = [var.vlan_tag]

  variables {
    vlan_tag = 4095
  }
}

# ── edge_availability_domain ───────────────────────────────────────────────────

run "accepts_availability_domain_1" {
  command = plan

  variables {
    edge_availability_domain = "AVAILABILITY_DOMAIN_1"
  }
}

run "accepts_availability_domain_2" {
  command = plan

  variables {
    edge_availability_domain = "AVAILABILITY_DOMAIN_2"
  }
}

run "accepts_availability_domain_any" {
  command = plan

  variables {
    edge_availability_domain = "AVAILABILITY_DOMAIN_ANY"
  }
}

run "rejects_invalid_availability_domain" {
  command = plan

  expect_failures = [var.edge_availability_domain]

  variables {
    edge_availability_domain = "AVAILABILITY_DOMAIN_3"
  }
}

# ── mtu ────────────────────────────────────────────────────────────────────────

run "accepts_mtu_1440" {
  command = plan

  variables {
    mtu = 1440
  }
}

run "accepts_mtu_1460" {
  command = plan

  variables {
    mtu = 1460
  }
}

run "accepts_mtu_1500" {
  command = plan

  variables {
    mtu = 1500
  }
}

run "accepts_mtu_8896" {
  command = plan

  variables {
    mtu = 8896
  }
}

run "rejects_invalid_mtu" {
  command = plan

  expect_failures = [var.mtu]

  variables {
    mtu = 9000
  }
}

# ── encryption ─────────────────────────────────────────────────────────────────

run "accepts_none_encryption" {
  command = plan

  variables {
    encryption = "NONE"
  }
}

run "accepts_ipsec_encryption" {
  command = plan

  variables {
    encryption = "IPSEC"
  }
}

run "rejects_invalid_encryption" {
  command = plan

  expect_failures = [var.encryption]

  variables {
    encryption = "TLS"
  }
}
