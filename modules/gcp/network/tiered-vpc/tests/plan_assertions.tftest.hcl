# Plan assertions for network/tiered-vpc: subnet layout, CIDR derivation,
# baseline firewall and guards. Names and CIDRs here are the contract that lets
# stages/host callers migrate with moved blocks (no replacement).

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id = "mock-project"
  name       = "mock-vpc"
  region     = "europe-west1"
  cidr_block = "10.0.0.0/16"
  zones      = ["europe-west1-b", "europe-west1-c"]
}

run "three_tier_subnets_derived_and_hardened" {
  command = plan

  assert {
    condition     = toset(keys(module.private_subnets)) == toset(var.zones) && toset(keys(module.public_subnets)) == toset(keys(module.database_subnets))
    error_message = "One subnet per tier must be planned per zone, keyed by zone name."
  }

  assert {
    condition     = module.public_subnets["europe-west1-b"].subnet.name == "mock-vpc-public-europe-west1-b" && module.private_subnets["europe-west1-c"].subnet.name == "mock-vpc-private-europe-west1-c" && module.database_subnets["europe-west1-b"].subnet.name == "mock-vpc-db-europe-west1-b"
    error_message = "Subnet names must be derived as <name>-<tier>-<zone>."
  }

  assert {
    condition     = [for z in var.zones : module.public_subnets[z].subnet.ip_cidr_range] == ["10.0.0.0/24", "10.0.1.0/24"] && [for z in var.zones : module.private_subnets[z].subnet.ip_cidr_range] == ["10.0.16.0/24", "10.0.17.0/24"] && [for z in var.zones : module.database_subnets[z].subnet.ip_cidr_range] == ["10.0.32.0/24", "10.0.33.0/24"]
    error_message = "Auto CIDRs must be cidrsubnet(cidr_block, 8, i / 16+i / 32+i) for public / private / database."
  }

  assert {
    condition = alltrue(concat(
      [for s in module.private_subnets : s.subnet.private_ip_google_access],
      [for s in module.database_subnets : s.subnet.private_ip_google_access],
    ))
    error_message = "Private and database subnets must have Private Google Access enabled."
  }

  assert {
    condition = alltrue([
      for s in concat(values(module.public_subnets), values(module.private_subnets), values(module.database_subnets)) :
      length(s.subnet.log_config) == 1 && s.subnet.log_config[0].aggregation_interval == "INTERVAL_5_SEC" && s.subnet.log_config[0].flow_sampling == 0.5
    ])
    error_message = "Every subnet must have flow logs on with the default 5s / 0.5 settings."
  }

  assert {
    condition     = module.vpc.network.auto_create_subnetworks == false && module.vpc.network.delete_default_routes_on_create == true
    error_message = "The VPC must be custom-mode with the default internet route deleted on create."
  }
}

run "explicit_cidrs_and_secondary_ranges" {
  command = plan

  variables {
    subnet_cidrs = {
      private = ["10.0.100.0/24", "10.0.101.0/24"]
    }
    secondary_ranges = {
      "europe-west1-b" = [{ range_name = "pods", ip_cidr_range = "10.8.0.0/16" }]
    }
  }

  assert {
    condition     = module.private_subnets["europe-west1-c"].subnet.ip_cidr_range == "10.0.101.0/24" && module.public_subnets["europe-west1-c"].subnet.ip_cidr_range == "10.0.1.0/24"
    error_message = "An explicit tier list must win for that tier only; other tiers stay derived."
  }

  assert {
    condition     = length(module.private_subnets["europe-west1-b"].subnet.secondary_ip_range) == 1 && length(module.private_subnets["europe-west1-c"].subnet.secondary_ip_range) == 0
    error_message = "Secondary ranges must attach only to the private subnet of the keyed zone."
  }
}

run "firewall_baseline" {
  command = plan

  assert {
    condition = toset([
      module.firewall_apigateway_to_public.name,
      module.firewall_public_to_compute.name,
      module.firewall_compute_to_database.name,
      module.firewall_health_checks.name,
      module.firewall_iap_ssh_rdp[0].name,
      module.firewall_database_deny_egress.name,
      module.firewall_deny_all.name,
      ]) == toset([
      "mock-vpc-allow-apigw-public",
      "mock-vpc-allow-public-compute",
      "mock-vpc-allow-compute-db",
      "mock-vpc-allow-health-checks",
      "mock-vpc-allow-iap-ssh-rdp",
      "mock-vpc-deny-db-egress",
      "mock-vpc-deny-all-ingress",
    ])
    error_message = "The tiered allow rules, health checks, IAP, database egress deny and catch-all deny must all be planned with <name>-derived names."
  }
}

run "toggles_and_guards" {
  command = plan

  variables {
    deletion_protection = true
    shared_vpc_host     = true
    firewall = {
      enable_iap_access = false
    }
  }

  assert {
    condition     = length(module.firewall_iap_ssh_rdp) == 0
    error_message = "firewall.enable_iap_access = false must drop only the IAP rule."
  }

  assert {
    condition     = terraform_data.deletion_protection_guard[0].input == "mock-project/mock-vpc"
    error_message = "The deletion guard must be keyed '<project_id>/<name>' when enabled."
  }

  assert {
    condition     = output.network_name == "mock-vpc" && output.network_tags.database == "database"
    error_message = "The module must expose the VPC name and the tier network tags."
  }
}
