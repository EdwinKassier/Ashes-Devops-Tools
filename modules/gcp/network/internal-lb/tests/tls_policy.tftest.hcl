# TLS floor of the L7 HTTPS path: with no ssl_policy_id the module creates a
# regional MODERN TLS 1.2 SSL policy and attaches it to the regional HTTPS
# proxy. Without one, Google uses COMPATIBLE (TLS 1.0 minimum).
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id       = "mock-project"
  name             = "test-lb"
  region           = "europe-west1"
  network          = "projects/mock-project/global/networks/mock-vpc"
  subnet           = "projects/mock-project/regions/europe-west1/subnetworks/mock-subnet"
  is_l7            = true
  enable_ssl       = true
  ssl_certificates = ["projects/mock-project/regions/europe-west1/sslCertificates/mock-cert"]
  host_rules = [
    {
      hosts        = ["example.com"]
      path_matcher = "main"
    }
  ]
  path_matchers = [
    {
      name            = "main"
      default_service = "projects/mock-project/regions/europe-west1/backendServices/mock-bs"
    }
  ]
  backends = [
    {
      group = "projects/mock-project/zones/europe-west1-b/instanceGroups/mock-ig"
    }
  ]
}

run "default_tls_policy_is_modern_tls_1_2" {
  command = plan

  assert {
    condition     = length(google_compute_region_ssl_policy.this) == 1
    error_message = "an L7 HTTPS load balancer with no ssl_policy_id must get a regional SSL policy"
  }

  assert {
    condition = (
      google_compute_region_ssl_policy.this[0].min_tls_version == "TLS_1_2" &&
      google_compute_region_ssl_policy.this[0].profile == "MODERN" &&
      google_compute_region_ssl_policy.this[0].region == "europe-west1" &&
      google_compute_region_ssl_policy.this[0].name == "test-lb-tls"
    )
    error_message = "the default SSL policy must be MODERN, TLS 1.2 minimum, named <name>-tls, in var.region"
  }
}

run "tls_1_3_with_restricted_profile" {
  command = plan

  variables {
    min_tls_version    = "TLS_1_3"
    ssl_policy_profile = "RESTRICTED"
  }

  assert {
    condition     = google_compute_region_ssl_policy.this[0].min_tls_version == "TLS_1_3" && google_compute_region_ssl_policy.this[0].profile == "RESTRICTED"
    error_message = "min_tls_version and ssl_policy_profile must reach the SSL policy"
  }
}

run "caller_ssl_policy_wins" {
  command = plan

  variables {
    ssl_policy_id = "projects/mock-project/regions/europe-west1/sslPolicies/caller-policy"
  }

  assert {
    condition     = length(google_compute_region_ssl_policy.this) == 0
    error_message = "a caller ssl_policy_id must suppress the module's SSL policy"
  }

  assert {
    condition     = google_compute_region_target_https_proxy.https_proxy[0].ssl_policy == "projects/mock-project/regions/europe-west1/sslPolicies/caller-policy"
    error_message = "a caller ssl_policy_id must be set on the HTTPS proxy as is"
  }
}

# No HTTPS proxy, no SSL policy: plain HTTP L7 and the L4 path create none.
run "no_policy_without_https" {
  command = plan

  variables {
    enable_ssl = false
  }

  assert {
    condition     = length(google_compute_region_ssl_policy.this) == 0
    error_message = "the SSL policy must only exist with the HTTPS proxy"
  }
}

run "rejects_tls_1_0_minimum" {
  command = plan

  variables {
    min_tls_version = "TLS_1_0"
  }

  expect_failures = [var.min_tls_version]
}

run "rejects_tls_1_3_without_restricted_profile" {
  command = plan

  variables {
    min_tls_version    = "TLS_1_3"
    ssl_policy_profile = "MODERN"
  }

  expect_failures = [var.ssl_policy_profile]
}
