# Hub VPC-SC perimeter scope, the opt-in Secure Web Proxy and the data-plane
# alert plumbing through the network-hub stage. module.hub is NOT overridden:
# only its zone lookup and tiered VPC core are stubbed, so the perimeter inputs
# are checked on the planned vpc-sc module.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_prefix         = "mock"
  hub_vpc_cidr_block     = "10.0.0.0/16"
  dns_hub_vpc_cidr_block = "10.1.0.0/16"
  default_region         = "us-central1"
  hub_project_id         = "mock-hub-project"
  dns_project_id         = "mock-dns-project"
  spoke_project_numbers  = { dev = "333333333333", prod = "444444444444" }
  hub_project_number     = "111111111111"
  dns_project_number     = "222222222222"
  org_id                 = "organizations/123456789"
  internal_domain        = "internal.example.com"
  folders = {
    shared = { id = "folders/111111111", name = "folders/111111111", display_name = "Shared" }
  }
}

override_data {
  target = module.hub.data.google_compute_zones.available
  values = {
    names = ["us-central1-a"]
  }
}

override_module {
  target = module.hub.module.network
  outputs = {
    network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core"
    network_id        = "projects/mock-hub-project/global/networks/hub-vpc-core"
    network_name      = "hub-vpc-core"
    subnets = {
      public = {}
      private = {
        "us-central1-a" = {
          id        = "projects/mock-hub-project/regions/us-central1/subnetworks/hub-vpc-core-private-us-central1-a"
          self_link = "https://www.googleapis.com/compute/v1/projects/mock-hub-project/regions/us-central1/subnetworks/hub-vpc-core-private-us-central1-a"
        }
      }
      database = {}
    }
  }
}

override_data {
  target = module.dns_anchor.data.google_compute_zones.available
  values = {
    names = ["us-central1-a"]
  }
}

override_module {
  target = module.dns_anchor.module.network
  outputs = {
    network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core"
    network_id        = "projects/mock-dns-project/global/networks/dns-vpc-core"
    network_name      = "dns-vpc-core"
    subnets           = { public = {}, private = {}, database = {} }
  }
}


run "hub_perimeter_holds_hub_and_dns_only" {
  command = plan

  variables {
    vpc_sc_access_policy_name = "1234567890"
    vpc_sc_enable_dry_run     = false
  }

  assert {
    condition     = output.hub_perimeter_projects == tolist(["111111111111", "222222222222"])
    error_message = "The hub perimeter must hold the hub and DNS projects only."
  }

  assert {
    condition     = module.hub.vpc_service_controls["hub_data_perimeter"].protected_project_numbers == tolist(["111111111111", "222222222222"])
    error_message = "No environment host project may be in the hub perimeter (each has its own environment perimeter, and a project can be in only one regular perimeter of a policy)."
  }

  assert {
    condition     = !contains(module.hub.vpc_service_controls["hub_data_perimeter"].protected_project_numbers, "333333333333") && !contains(module.hub.vpc_service_controls["hub_data_perimeter"].protected_project_numbers, "444444444444")
    error_message = "Dev and prod host projects must stay out of the shared hub perimeter."
  }
}

run "spoke_numbers_still_feed_ncc_auto_accept" {
  command = plan

  variables {
    enable_ncc_hub = true
  }

  assert {
    condition     = local.ncc_auto_accept_projects == tolist(["333333333333", "444444444444"])
    error_message = "spoke_project_numbers must keep feeding the NCC auto-accept list."
  }
}

run "secure_web_proxy_off_by_default" {
  command = plan

  assert {
    condition     = output.secure_web_proxy == null
    error_message = "The Secure Web Proxy must be opt-in."
  }
}

run "published_proxy_accepts_environment_host_projects_by_default" {
  command = plan

  variables {
    secure_web_proxy = {
      enabled             = true
      allowed_fqdns       = ["*.github.com"]
      psc_nat_subnet_cidr = "10.0.253.0/24"
    }
  }

  assert {
    condition     = local.secure_web_proxy.consumer_accept_projects == tolist(["333333333333", "444444444444"])
    error_message = "With no explicit consumers the published proxy must accept the environment host projects."
  }
}

run "published_proxy_explicit_consumers_win" {
  command = plan

  variables {
    secure_web_proxy = {
      enabled                  = true
      psc_nat_subnet_cidr      = "10.0.253.0/24"
      consumer_accept_projects = ["555555555555"]
    }
  }

  assert {
    condition     = local.secure_web_proxy.consumer_accept_projects == tolist(["555555555555"])
    error_message = "An explicit consumer_accept_projects list must win over the environment default."
  }
}
