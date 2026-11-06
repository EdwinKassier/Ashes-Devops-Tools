# Behaviour suite: assert the composed load balancer is secure by default,
# redirects HTTP to HTTPS, and conditionally creates DNS records.

mock_provider "google" {}

variables {
  project_id             = "acme-host-abcd"
  region                 = "europe-west1"
  name                   = "my-api"
  domains                = ["api.example.com"]
  cloud_run_service_name = "my-api"
}

run "front_door_is_secure_by_default" {
  command = plan

  # Managed cert covers the requested domain.
  assert {
    condition     = contains(google_compute_managed_ssl_certificate.this.managed[0].domains, "api.example.com")
    error_message = "the managed certificate must cover the requested domain."
  }

  # Backend access logging is on.
  assert {
    condition     = google_compute_backend_service.this.log_config[0].enable == true
    error_message = "backend access logging must be enabled on the front door."
  }

  # Backend speaks HTTPS to the serverless NEG.
  assert {
    condition     = google_compute_backend_service.this.protocol == "HTTPS"
    error_message = "the backend service must use HTTPS."
  }

  # HTTP listener redirects to HTTPS, so nothing is served in plaintext.
  assert {
    condition     = google_compute_url_map.redirect.default_url_redirect[0].https_redirect == true
    error_message = "the HTTP listener must redirect to HTTPS."
  }

  # Serverless NEG points at the named Cloud Run service.
  assert {
    condition     = google_compute_region_network_endpoint_group.this.cloud_run[0].service == "my-api"
    error_message = "the serverless NEG must target the named Cloud Run service."
  }

  # No DNS record when no managed zone is given.
  assert {
    condition     = length(google_dns_record_set.this) == 0
    error_message = "no DNS record should be created when dns_managed_zone is null."
  }
}

run "creates_dns_record_when_zone_set" {
  command = plan

  variables {
    dns_managed_zone = "app-zone"
    domains          = ["api.example.com", "www.example.com"]
  }

  assert {
    condition     = length(google_dns_record_set.this) == 2
    error_message = "one A record must be created per domain when a managed zone is set."
  }
}

run "attaches_cloud_armor_when_provided" {
  command = plan

  variables {
    security_policy_id = "projects/acme-host-abcd/global/securityPolicies/edge"
  }

  assert {
    condition     = google_compute_backend_service.this.security_policy == "projects/acme-host-abcd/global/securityPolicies/edge"
    error_message = "the Cloud Armor policy must attach to the backend service when provided."
  }
}

run "module_labels_applied" {
  command = plan

  variables {
    labels = { owner = "test" }

  }

  assert {
    condition     = google_compute_global_address.this.labels["owner"] == "test" && google_compute_global_forwarding_rule.https.labels["owner"] == "test"
    error_message = "var.labels must land on the global address and forwarding rule."
  }
}
