# Regression test: when create_router is true and router_name is unset (default ""),
# the router name must be auto-generated as "<nat name>-router".
# The base variables block intentionally omits router_name so the empty-name path
# is actually exercised (the validation test's base pins router_name and masks this bug).
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  name       = "test-nat"
  region     = "europe-west1"
  network    = "projects/mock-project/global/networks/mock-vpc"
  # router_name intentionally omitted → defaults to "" → auto-generation path.
}

run "auto_generates_router_name_when_unset" {
  command = plan

  assert {
    condition     = google_compute_router.router[0].name == "${var.name}-router"
    error_message = "router name must default to <nat name>-router when router_name is empty"
  }
}

# --- Behavioural plan assertions (defaults, toggles, conditional blocks) -----

run "secure_defaults" {
  command = plan

  assert {
    condition     = length(google_compute_router.router) == 1
    error_message = "create_router defaults to true and must plan exactly one Cloud Router."
  }

  assert {
    condition     = length(google_compute_router.router[0].bgp) == 0
    error_message = "No BGP block must be rendered when router_asn is unset."
  }

  assert {
    condition     = google_compute_router_nat.nat.router == "test-nat-router"
    error_message = "NAT must attach to the auto-created router (derived name)."
  }

  assert {
    condition     = length(google_compute_router_nat.nat.log_config) == 1
    error_message = "NAT logging must be enabled by default."
  }

  assert {
    condition     = google_compute_router_nat.nat.log_config[0].enable == true && google_compute_router_nat.nat.log_config[0].filter == "ERRORS_ONLY"
    error_message = "NAT logging must default to enable = true with filter ERRORS_ONLY."
  }

  assert {
    condition     = google_compute_router_nat.nat.nat_ip_allocate_option == "AUTO_ONLY"
    error_message = "Default NAT IP allocation must be AUTO_ONLY."
  }

  assert {
    condition     = google_compute_router_nat.nat.source_subnetwork_ip_ranges_to_nat == "ALL_SUBNETWORKS_ALL_IP_RANGES" && length(google_compute_router_nat.nat.subnetwork) == 0
    error_message = "Default source ranges must be ALL_SUBNETWORKS_ALL_IP_RANGES with no subnetwork blocks."
  }

  assert {
    condition     = google_compute_router_nat.nat.min_ports_per_vm == 64 && google_compute_router_nat.nat.tcp_established_idle_timeout_sec == 1200 && google_compute_router_nat.nat.tcp_time_wait_timeout_sec == 120
    error_message = "Port/timeout defaults (64 ports, 1200s established, 120s time-wait) must be applied."
  }
}

run "existing_router_manual_ips_subnet_list_no_logging" {
  command = plan

  variables {
    create_router                      = false
    router_name                        = "shared-router"
    nat_ip_allocate_option             = "MANUAL_ONLY"
    nat_ips                            = ["projects/mock-project/regions/europe-west1/addresses/nat-ip-1"]
    source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
    subnetworks = [
      {
        name                    = "projects/mock-project/regions/europe-west1/subnetworks/app"
        source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
      },
    ]
    enable_logging = false
  }

  assert {
    condition     = length(google_compute_router.router) == 0
    error_message = "create_router = false must not plan a router."
  }

  assert {
    condition     = google_compute_router_nat.nat.router == "shared-router"
    error_message = "NAT must attach to the supplied existing router."
  }

  assert {
    condition     = length(google_compute_router_nat.nat.nat_ips) == 1
    error_message = "MANUAL_ONLY must pass the supplied NAT IPs through."
  }

  assert {
    condition     = length(google_compute_router_nat.nat.subnetwork) == 1
    error_message = "LIST_OF_SUBNETWORKS must render one subnetwork block per entry."
  }

  assert {
    condition     = length(google_compute_router_nat.nat.log_config) == 0
    error_message = "enable_logging = false must drop the log_config block."
  }
}

run "subnetworks_ignored_unless_list_mode_and_bgp_asn" {
  command = plan

  variables {
    router_asn = 64514
    subnetworks = [
      {
        name                    = "projects/mock-project/regions/europe-west1/subnetworks/app"
        source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
      },
    ]
  }

  assert {
    condition     = length(google_compute_router_nat.nat.subnetwork) == 0
    error_message = "subnetworks must be ignored unless source_subnetwork_ip_ranges_to_nat = LIST_OF_SUBNETWORKS."
  }

  assert {
    condition     = google_compute_router.router[0].bgp[0].asn == 64514
    error_message = "router_asn must render a BGP block on the created router."
  }
}
