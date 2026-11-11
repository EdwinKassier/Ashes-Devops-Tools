# Plan assertions for modules/gcp/network/secure-web-proxy. mock_provider: no
# GCP credentials needed.

mock_provider "google" {
  mock_resource "google_network_services_gateway" {
    defaults = {
      id = "projects/mock-hub-project/locations/us-central1/gateways/hub-swp"
    }
  }
  mock_resource "google_network_security_url_lists" {
    defaults = {
      id = "projects/mock-hub-project/locations/us-central1/urlLists/hub-swp-allowlist"
    }
  }
  mock_resource "google_compute_subnetwork" {
    defaults = {
      id = "projects/mock-hub-project/regions/us-central1/subnetworks/hub-swp-psc-nat"
    }
  }
}

variables {
  project_id = "mock-hub-project"
  name       = "hub-swp"
  region     = "us-central1"
  network    = "projects/mock-hub-project/global/networks/hub-vpc"
  subnetwork = "projects/mock-hub-project/regions/us-central1/subnetworks/hub-private"
}

run "explicit_gateway_denies_by_default" {
  command = plan

  assert {
    condition = (
      google_network_services_gateway.this.type == "SECURE_WEB_GATEWAY" &&
      google_network_services_gateway.this.routing_mode == "EXPLICIT_ROUTING_MODE" &&
      google_network_services_gateway.this.ports == tolist([443])
    )
    error_message = "The gateway must be an explicit-mode SECURE_WEB_GATEWAY on port 443 by default."
  }

  assert {
    condition     = length(google_network_security_url_lists.allowlist) == 0 && length(google_network_security_gateway_security_policy_rule.allowlist) == 0
    error_message = "With no allowed_fqdns there is no allow rule, so the proxy denies everything."
  }

  assert {
    condition     = length(google_compute_subnetwork.proxy_only) == 0 && length(google_compute_service_attachment.this) == 0 && length(google_compute_subnetwork.psc_nat) == 0
    error_message = "Proxy-only subnet and PSC publishing must be opt-in."
  }

  assert {
    condition     = google_network_services_gateway.this.delete_swg_autogen_router_on_destroy == true
    error_message = "The gateway must clean up its auto-generated router on destroy."
  }
}

run "fqdn_allowlist_becomes_url_list_and_allow_rule" {
  command = apply

  variables {
    allowed_fqdns = ["*.github.com", "pypi.org"]
  }

  assert {
    condition     = google_network_security_url_lists.allowlist[0].values == tolist(["*.github.com", "pypi.org"])
    error_message = "The URL list must hold the allowlisted FQDNs."
  }

  assert {
    condition = (
      google_network_security_gateway_security_policy_rule.allowlist[0].basic_profile == "ALLOW" &&
      google_network_security_gateway_security_policy_rule.allowlist[0].priority == 1000 &&
      google_network_security_gateway_security_policy_rule.allowlist[0].session_matcher == "inUrlList(host(), 'projects/mock-hub-project/locations/us-central1/urlLists/hub-swp-allowlist')"
    )
    error_message = "The allowlist rule must ALLOW hosts in the URL list at priority 1000."
  }
}

run "additional_rules_planned" {
  command = plan

  variables {
    additional_rules = {
      deny-paste = { priority = 500, action = "DENY", session_matcher = "host() == 'pastebin.com'" }
    }
  }

  assert {
    condition     = google_network_security_gateway_security_policy_rule.additional["deny-paste"].basic_profile == "DENY" && google_network_security_gateway_security_policy_rule.additional["deny-paste"].priority == 500
    error_message = "additional_rules must become policy rules with their action and priority."
  }
}

run "proxy_only_subnet_created_on_request" {
  command = plan

  variables {
    create_proxy_only_subnet = true
    proxy_only_subnet_cidr   = "10.0.254.0/23"
  }

  assert {
    condition = (
      google_compute_subnetwork.proxy_only[0].purpose == "REGIONAL_MANAGED_PROXY" &&
      google_compute_subnetwork.proxy_only[0].role == "ACTIVE" &&
      google_compute_subnetwork.proxy_only[0].ip_cidr_range == "10.0.254.0/23"
    )
    error_message = "The proxy-only subnet must be an ACTIVE REGIONAL_MANAGED_PROXY subnet."
  }
}

run "service_attachment_accepts_listed_projects_only" {
  command = apply

  variables {
    create_service_attachment = true
    psc_nat_subnet_cidr       = "10.0.253.0/24"
    consumer_accept_projects  = ["111111111111", "222222222222"]
  }

  assert {
    condition     = google_compute_subnetwork.psc_nat[0].purpose == "PRIVATE_SERVICE_CONNECT"
    error_message = "The PSC NAT subnet must have purpose PRIVATE_SERVICE_CONNECT."
  }

  assert {
    condition = (
      google_compute_service_attachment.this[0].connection_preference == "ACCEPT_MANUAL" &&
      length(google_compute_service_attachment.this[0].consumer_accept_lists) == 2 &&
      google_compute_service_attachment.this[0].target_service == "//networkservices.googleapis.com/projects/mock-hub-project/locations/us-central1/gateways/hub-swp"
    )
    error_message = "The service attachment must target the gateway URI and accept only the listed projects."
  }
}

run "next_hop_mode_and_static_address" {
  command = plan

  variables {
    routing_mode = "NEXT_HOP_ROUTING_MODE"
    address      = "10.0.16.10"
  }

  assert {
    condition     = google_network_services_gateway.this.routing_mode == "NEXT_HOP_ROUTING_MODE" && google_network_services_gateway.this.addresses == tolist(["10.0.16.10"])
    error_message = "routing_mode and address must reach the gateway."
  }

  assert {
    condition     = output.gateway_address == "10.0.16.10"
    error_message = "gateway_address must echo a static address."
  }
}
