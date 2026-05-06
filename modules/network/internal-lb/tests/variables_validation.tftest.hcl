# Variable validation tests for the internal-lb module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  name       = "test-lb"
  region     = "europe-west1"
  network    = "projects/mock-project/global/networks/mock-vpc"
  subnet     = "projects/mock-project/regions/europe-west1/subnetworks/mock-subnet"
  backends = [
    {
      group = "projects/mock-project/zones/europe-west1-b/instanceGroups/mock-ig"
    }
  ]
}

# ── name ───────────────────────────────────────────────────────────────────────

run "accepts_valid_name" {
  command = plan

  variables {
    name = "my-internal-lb"
  }
}

run "accepts_name_with_numbers" {
  command = plan

  variables {
    name = "lb01"
  }
}

run "rejects_name_starting_with_digit" {
  command = plan

  expect_failures = [var.name]

  variables {
    name = "1-invalid-lb"
  }
}

run "rejects_name_with_uppercase" {
  command = plan

  expect_failures = [var.name]

  variables {
    name = "MyLB"
  }
}

# ── health_check_type ──────────────────────────────────────────────────────────

run "accepts_http_health_check" {
  command = plan

  variables {
    health_check_type = "HTTP"
  }
}

run "accepts_tcp_health_check" {
  command = plan

  variables {
    health_check_type = "TCP"
  }
}

run "accepts_grpc_health_check" {
  command = plan

  variables {
    health_check_type = "GRPC"
  }
}

run "rejects_invalid_health_check_type" {
  command = plan

  expect_failures = [var.health_check_type]

  variables {
    health_check_type = "UDP"
  }
}

# ── session_affinity ───────────────────────────────────────────────────────────

run "accepts_none_session_affinity" {
  command = plan
  variables {
    session_affinity = "NONE"
  }
}

run "accepts_client_ip_session_affinity" {
  command = plan
  variables {
    session_affinity = "CLIENT_IP"
  }
}

run "rejects_invalid_session_affinity" {
  command         = plan
  expect_failures = [var.session_affinity]
  variables {
    session_affinity = "COOKIE"
  }
}

# ── locality_lb_policy ─────────────────────────────────────────────────────────

run "accepts_round_robin_lb_policy" {
  command = plan
  variables {
    locality_lb_policy = "ROUND_ROBIN"
  }
}

run "accepts_least_request_lb_policy" {
  command = plan
  variables {
    locality_lb_policy = "LEAST_REQUEST"
  }
}

run "rejects_invalid_lb_policy" {
  command         = plan
  expect_failures = [var.locality_lb_policy]
  variables {
    locality_lb_policy = "WEIGHTED_ROUND_ROBIN"
  }
}
