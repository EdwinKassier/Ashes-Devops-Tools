# Plan assertions for the subnet module: verify secure-by-default settings
# (Private Google Access, VPC flow logs), conditional log_config, and secondary
# range rendering. All runs use mock_provider (no GCP credentials).

mock_provider "google" {}

variables {
  project_id    = "mock-project"
  subnet_name   = "mock-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = "europe-west1"
  network       = "projects/mock-project/global/networks/mock-vpc"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = google_compute_subnetwork.subnet.private_ip_google_access == true
    error_message = "Private Google Access must be enabled by default."
  }

  assert {
    condition     = length(google_compute_subnetwork.subnet.log_config) == 1
    error_message = "VPC flow logs (log_config) must be enabled by default."
  }

  assert {
    condition     = google_compute_subnetwork.subnet.log_config[0].aggregation_interval == "INTERVAL_5_SEC"
    error_message = "Flow log aggregation interval must default to INTERVAL_5_SEC."
  }

  assert {
    condition     = google_compute_subnetwork.subnet.log_config[0].flow_sampling == 0.5
    error_message = "Flow log sampling must default to 0.5."
  }

  assert {
    condition     = google_compute_subnetwork.subnet.log_config[0].metadata == "INCLUDE_ALL_METADATA"
    error_message = "Flow logs must include all metadata by default."
  }

  assert {
    condition     = length(google_compute_subnetwork.subnet.secondary_ip_range) == 0
    error_message = "No secondary ranges must be rendered when none are supplied."
  }

  assert {
    condition     = google_compute_subnetwork.subnet.role == null
    error_message = "role must be left unset unless a proxy-only purpose is supplied."
  }
}

run "flow_logs_disabled_removes_log_config" {
  command = plan

  variables {
    enable_flow_logs         = false
    private_ip_google_access = false
  }

  assert {
    condition     = length(google_compute_subnetwork.subnet.log_config) == 0
    error_message = "enable_flow_logs = false must drop the log_config block."
  }

  assert {
    condition     = google_compute_subnetwork.subnet.private_ip_google_access == false
    error_message = "private_ip_google_access override must be honoured."
  }
}

run "secondary_ranges_and_proxy_subnet" {
  command = plan

  variables {
    secondary_ip_ranges = [
      { range_name = "pods", ip_cidr_range = "10.100.0.0/16" },
      { range_name = "services", ip_cidr_range = "10.200.0.0/20" },
    ]
    purpose = "REGIONAL_MANAGED_PROXY"
    role    = "ACTIVE"
  }

  assert {
    condition     = length(google_compute_subnetwork.subnet.secondary_ip_range) == 2
    error_message = "Each secondary_ip_ranges entry must render one secondary_ip_range block."
  }

  assert {
    condition     = toset([for r in google_compute_subnetwork.subnet.secondary_ip_range : r.range_name]) == toset(["pods", "services"])
    error_message = "Secondary range names must match the supplied entries."
  }

  assert {
    condition     = google_compute_subnetwork.subnet.purpose == "REGIONAL_MANAGED_PROXY" && google_compute_subnetwork.subnet.role == "ACTIVE"
    error_message = "Proxy-only subnet purpose/role must be wired through."
  }
}
