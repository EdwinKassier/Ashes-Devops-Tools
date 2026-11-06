# State migration: module "host" source stages/host -> stages/net-spoke.
#
# The module label is unchanged, so every service-level address (NAT, PSA,
# PSC, Cloud Armor, peering, DNS, flow-log export, VPC-SC, Shared VPC service
# projects, additional firewall rules) keeps its exact address inside
# module.host. Only the network core moved: it now lives in the shared
# network/tiered-vpc building block (module.host.module.network), where the
# always-on resources are no longer count-gated ([0] -> bare address).
#
# Keep these blocks for at least one release after every gcp-workload-<env>
# workspace has applied; removing one early turns its move into
# destroy/create.

moved {
  from = module.host.terraform_data.deletion_protection_guard
  to   = module.host.module.network.terraform_data.deletion_protection_guard
}

moved {
  from = module.host.terraform_data.subnet_cidr_count_guard[0]
  to   = module.host.module.network.terraform_data.subnet_cidr_count_guard
}

moved {
  from = module.host.module.vpc[0]
  to   = module.host.module.network.module.vpc
}

moved {
  from = module.host.module.public_subnets
  to   = module.host.module.network.module.public_subnets
}

moved {
  from = module.host.module.private_subnets
  to   = module.host.module.network.module.private_subnets
}

moved {
  from = module.host.module.database_subnets
  to   = module.host.module.network.module.database_subnets
}

moved {
  from = module.host.module.firewall_apigateway_to_public[0]
  to   = module.host.module.network.module.firewall_apigateway_to_public
}

moved {
  from = module.host.module.firewall_public_to_compute[0]
  to   = module.host.module.network.module.firewall_public_to_compute
}

moved {
  from = module.host.module.firewall_compute_to_database[0]
  to   = module.host.module.network.module.firewall_compute_to_database
}

moved {
  from = module.host.module.firewall_health_checks[0]
  to   = module.host.module.network.module.firewall_health_checks
}

moved {
  from = module.host.module.firewall_database_deny_egress[0]
  to   = module.host.module.network.module.firewall_database_deny_egress
}

moved {
  from = module.host.module.firewall_deny_all[0]
  to   = module.host.module.network.module.firewall_deny_all
}

moved {
  from = module.host.module.firewall_iap_ssh_rdp
  to   = module.host.module.network.module.firewall_iap_ssh_rdp
}
