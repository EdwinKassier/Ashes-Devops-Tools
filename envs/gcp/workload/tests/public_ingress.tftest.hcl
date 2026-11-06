# Public ingress (modules/gcp/network/app-ingress) and the first-revision image
# for app services. Real host stage against mocks (zones overridden).

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  landing_zone_config_path = ""
  project_prefix           = "acme"
  environment              = "dev"
  tfc_organization         = "acme-tfc"
  monthly_budget_limit     = 0
  enable_network_hub       = false
  organization_contract = {
    org_id               = "123456789012"
    billing_account      = "billingAccounts/000000-111111-222222"
    admin_project_number = "111111111111"
  }
  projects_contract = {
    environment_config = {
      dev = {
        folder_id           = "folders/111"
        host_project_id     = "acme-dev-host-abcd"
        host_project_number = "222222222222"
        region              = "europe-west2"
        cidr_block          = "10.10.0.0/16"
      }
    }
  }
  app_services = {
    api    = {}
    worker = {}
  }
}

override_data {
  target = module.host.data.google_compute_zones.available
  values = {
    names = ["europe-west2-a", "europe-west2-b", "europe-west2-c"]
  }
}

run "default_has_no_public_ingress" {
  command = plan

  assert {
    condition     = length(module.app_ingress) == 0 && length(output.public_ingress) == 0
    error_message = "Public ingress must be off by default."
  }

  assert {
    condition     = module.app_services.services["api"].initial_image == "us-docker.pkg.dev/cloudrun/container/hello"
    error_message = "The first revision defaults to the public Cloud Run sample."
  }

  assert {
    condition     = module.host.cloud_armor == null
    error_message = "No Cloud Armor policy without public ingress or enable_cloud_armor."
  }
}

run "public_ingress_creates_lb_neg_armor_and_cert" {
  command = plan

  variables {
    public_ingress_services = {
      api = { domains = ["api.dev.acme.example"] }
    }
  }

  assert {
    condition     = length(module.app_ingress) == 1 && contains(keys(module.app_ingress), "api")
    error_message = "Only the listed service is exposed."
  }

  assert {
    condition     = one(module.app_ingress["api"].managed_domains) == "api.dev.acme.example"
    error_message = "The managed certificate must cover the configured domains."
  }

  assert {
    condition     = module.host.cloud_armor != null
    error_message = "Public ingress must create the environment Cloud Armor policy (attached to the backend)."
  }

  assert {
    condition = (
      local.app_services["api"].ingress == "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" &&
      local.app_services["api"].enable_unauthenticated &&
      local.app_services["worker"].ingress == "INGRESS_TRAFFIC_INTERNAL_ONLY" &&
      !local.app_services["worker"].enable_unauthenticated
    )
    error_message = "Exposed services switch to LB-only ingress; the rest stay internal."
  }
}

# Applied (mocked) so the load balancer's computed IDs are concrete: the backend
# service (serverless NEG -> Cloud Run) and the HTTPS forwarding rule exist.
run "public_ingress_backend_and_neg_exist" {
  command = apply

  variables {
    public_ingress_services = {
      api = { domains = ["api.dev.acme.example"] }
    }
    enable_vm_backup_policy    = false
    enable_os_patch_management = false
  }

  # Isolate the load balancer: the host stage and app services are covered by
  # the plan runs above; their mocked applies trip unrelated provider checks.
  override_module {
    target = module.host
    outputs = {
      dns_zones                 = {}
      nat_ip                    = "34.1.2.3"
      network_id                = "projects/acme-dev-host-abcd/global/networks/acme-dev-vpc"
      network_name              = "acme-dev-vpc"
      network_self_link         = "https://www.googleapis.com/compute/v1/projects/acme-dev-host-abcd/global/networks/acme-dev-vpc"
      security_policy_id        = "projects/acme-dev-host-abcd/global/securityPolicies/acme-dev-armor"
      security_policy_self_link = "https://www.googleapis.com/compute/v1/projects/acme-dev-host-abcd/global/securityPolicies/acme-dev-armor"
      subnets                   = {}
      vpc_peerings              = {}
      vpc_service_controls      = {}
    }
  }

  override_module {
    target = module.app_services
    outputs = {
      services = {
        api    = { service_name = "api", initial_image = "us-docker.pkg.dev/cloudrun/container/hello" }
        worker = { service_name = "worker", initial_image = "us-docker.pkg.dev/cloudrun/container/hello" }
      }
      workload_identity_provider = null
      github_actions             = {}
      gke_cluster_name           = null
    }
  }

  assert {
    condition     = module.app_ingress["api"].backend_service_id != null && module.app_ingress["api"].https_forwarding_rule_id != null
    error_message = "Public ingress must create the backend service and HTTPS forwarding rule."
  }

  assert {
    condition     = length(output.public_ingress) == 1 && output.public_ingress["api"].ip_address != null
    error_message = "The load balancer IP must be exposed for DNS."
  }
}

run "public_ingress_from_config_and_bootstrap_image" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-app.yaml"
  }

  assert {
    condition     = length(module.app_ingress) == 1 && one(module.app_ingress["api"].managed_domains) == "api.dev.cfg.example"
    error_message = "gcp.workload.public_ingress.<env> must drive public ingress."
  }

  assert {
    condition     = module.app_services.services["api"].initial_image == "europe-west2-docker.pkg.dev/acme-dev-host-abcd/mirror/hello:bootstrap"
    error_message = "gcp.workload.bootstrap_image must override the first-revision image."
  }
}

run "public_ingress_can_be_switched_off" {
  command = plan

  variables {
    enable_public_ingress   = false
    public_ingress_services = { api = { domains = ["api.dev.acme.example"] } }
  }

  assert {
    condition     = length(module.app_ingress) == 0
    error_message = "enable_public_ingress = false must create no load balancer."
  }
}

run "rejects_public_ingress_for_unknown_service" {
  command = plan

  variables {
    public_ingress_services = { billing = { domains = ["billing.dev.acme.example"] } }
  }

  expect_failures = [var.public_ingress_services]
}
