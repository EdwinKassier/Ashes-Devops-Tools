# Resource-assertion tests for the network/cdn module.
# Asserts that var.enable_cdn actually toggles both the backend service's
# enable_cdn attribute AND the presence of the cdn_policy dynamic block — prior
# tests only validated inputs.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  lb_name    = "test-lb"
  domains    = ["example.com"]
}

run "enable_cdn_true_wires_cdn_policy" {
  command = plan

  variables {
    enable_cdn = true
  }

  assert {
    condition     = google_compute_backend_service.default.enable_cdn == true
    error_message = "backend service enable_cdn must reflect var.enable_cdn = true."
  }

  assert {
    condition     = length(google_compute_backend_service.default.cdn_policy) == 1
    error_message = "The cdn_policy block must be present when enable_cdn = true."
  }
}

run "enable_cdn_false_omits_cdn_policy" {
  command = plan

  variables {
    enable_cdn = false
  }

  assert {
    condition     = google_compute_backend_service.default.enable_cdn == false
    error_message = "backend service enable_cdn must be false when disabled."
  }

  assert {
    condition     = length(google_compute_backend_service.default.cdn_policy) == 0
    error_message = "The cdn_policy block must be omitted when enable_cdn = false."
  }
}

run "module_labels_applied" {
  command = plan

  variables {
    labels = { owner = "test" }

  }

  assert {
    condition     = google_compute_global_address.default.labels["owner"] == "test" && google_compute_global_forwarding_rule.default.labels["owner"] == "test"
    error_message = "var.labels must land on the global address and forwarding rule."
  }
}

# TLS floor: with no ssl_policy_id the module creates a MODERN TLS 1.2 policy
# and attaches it to the HTTPS proxy. Without one, Google uses COMPATIBLE
# (TLS 1.0 minimum).
run "default_tls_policy_is_modern_tls_1_2" {
  command = plan

  assert {
    condition     = length(google_compute_ssl_policy.this) == 1
    error_message = "with no ssl_policy_id the module must create an SSL policy"
  }

  assert {
    condition     = google_compute_ssl_policy.this[0].min_tls_version == "TLS_1_2" && google_compute_ssl_policy.this[0].profile == "MODERN"
    error_message = "the default SSL policy must be MODERN with a TLS 1.2 minimum"
  }

  assert {
    condition     = google_compute_ssl_policy.this[0].name == "test-lb-tls"
    error_message = "the SSL policy must be named <lb_name>-tls"
  }
}

run "tls_1_3_with_restricted_profile" {
  command = plan

  variables {
    min_tls_version    = "TLS_1_3"
    ssl_policy_profile = "RESTRICTED"
  }

  assert {
    condition     = google_compute_ssl_policy.this[0].min_tls_version == "TLS_1_3" && google_compute_ssl_policy.this[0].profile == "RESTRICTED"
    error_message = "min_tls_version and ssl_policy_profile must reach the SSL policy"
  }
}

run "caller_ssl_policy_wins" {
  command = plan

  variables {
    ssl_policy_id = "projects/mock-project/global/sslPolicies/caller-policy"
  }

  assert {
    condition     = length(google_compute_ssl_policy.this) == 0
    error_message = "a caller ssl_policy_id must suppress the module's SSL policy"
  }

  assert {
    condition     = google_compute_target_https_proxy.default.ssl_policy == "projects/mock-project/global/sslPolicies/caller-policy"
    error_message = "a caller ssl_policy_id must be set on the HTTPS proxy as is"
  }
}
