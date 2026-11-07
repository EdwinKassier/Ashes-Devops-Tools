# Public ingress (modules/gcp/network/app-ingress) and the first-revision image
# for app services, as the root wires them into the environment stage (real stage
# against mocks, zones overridden). The load-balancer internals and the per-service
# ingress defaults are asserted in modules/gcp/stages/environment/tests.

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
  target = module.environment.module.host.data.google_compute_zones.available
  values = {
    names = ["europe-west2-a", "europe-west2-b", "europe-west2-c"]
  }
}

run "default_has_no_public_ingress" {
  command = plan

  assert {
    condition     = length(module.environment.components.public_ingress) == 0 && length(output.public_ingress) == 0
    error_message = "Public ingress must be off by default."
  }

  assert {
    condition     = output.app_services["api"].initial_image == "us-docker.pkg.dev/cloudrun/container/hello"
    error_message = "The first revision defaults to the public Cloud Run sample."
  }

  assert {
    condition     = !module.environment.components.cloud_armor
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
    condition     = module.environment.components.public_ingress == ["api"]
    error_message = "Only the listed service is exposed."
  }

  assert {
    condition     = one(output.public_ingress["api"].domains) == "api.dev.acme.example"
    error_message = "The managed certificate must cover the configured domains."
  }

  assert {
    condition     = module.environment.components.cloud_armor
    error_message = "Public ingress must create the environment Cloud Armor policy (attached to the backend)."
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
    target = module.environment.module.host
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
    target = module.environment.module.app_services
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
    condition     = module.environment.components.public_ingress == ["api"] && one(output.public_ingress["api"].domains) == "api.dev.cfg.example"
    error_message = "gcp.workload.public_ingress.<env> must drive public ingress."
  }

  assert {
    condition     = output.app_services["api"].initial_image == "europe-west2-docker.pkg.dev/acme-dev-host-abcd/mirror/hello:bootstrap"
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
    condition     = length(module.environment.components.public_ingress) == 0
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
