# State migration: stages/host -> net-hub / dns-anchor (one deprecation cycle).
#
# module.hub_network and module.dns_hub_network used the deprecated
# stages/host god-module. They are now module.hub (net-hub) and
# module.dns_anchor (dns-anchor), whose VPC core lives one level down in the
# shared network/tiered-vpc building block (module.<x>.module.network). Every
# object those two calls could hold, given the inputs this stage passed, is
# moved explicitly below so the first plan after the refactor is a no-op move
# (no destroy or create). Single-instance count = 1 resources that are now
# unconditional move from [0] to the bare address; for_each module calls with
# identical keys move as whole calls.
#
# Keep these blocks for at least one release after every workspace has
# applied; removing a moved block early turns the move into destroy/create.

# --- Hub network (net-hub): network core -> module.hub.module.network ---

moved {
  from = module.hub_network.terraform_data.deletion_protection_guard
  to   = module.hub.module.network.terraform_data.deletion_protection_guard
}

moved {
  from = module.hub_network.terraform_data.subnet_cidr_count_guard[0]
  to   = module.hub.module.network.terraform_data.subnet_cidr_count_guard
}

moved {
  from = module.hub_network.module.vpc[0]
  to   = module.hub.module.network.module.vpc
}

moved {
  from = module.hub_network.module.public_subnets
  to   = module.hub.module.network.module.public_subnets
}

moved {
  from = module.hub_network.module.private_subnets
  to   = module.hub.module.network.module.private_subnets
}

moved {
  from = module.hub_network.module.database_subnets
  to   = module.hub.module.network.module.database_subnets
}

moved {
  from = module.hub_network.module.firewall_apigateway_to_public[0]
  to   = module.hub.module.network.module.firewall_apigateway_to_public
}

moved {
  from = module.hub_network.module.firewall_public_to_compute[0]
  to   = module.hub.module.network.module.firewall_public_to_compute
}

moved {
  from = module.hub_network.module.firewall_compute_to_database[0]
  to   = module.hub.module.network.module.firewall_compute_to_database
}

moved {
  from = module.hub_network.module.firewall_health_checks[0]
  to   = module.hub.module.network.module.firewall_health_checks
}

moved {
  from = module.hub_network.module.firewall_database_deny_egress[0]
  to   = module.hub.module.network.module.firewall_database_deny_egress
}

moved {
  from = module.hub_network.module.firewall_deny_all[0]
  to   = module.hub.module.network.module.firewall_deny_all
}

moved {
  from = module.hub_network.module.firewall_iap_ssh_rdp
  to   = module.hub.module.network.module.firewall_iap_ssh_rdp
}

# --- Hub network: services that stay at the net-hub top level ---

moved {
  from = module.hub_network.module.integrated_nat
  to   = module.hub.module.integrated_nat
}

moved {
  from = module.hub_network.module.private_service_access
  to   = module.hub.module.private_service_access
}

moved {
  from = module.hub_network.module.private_service_connect
  to   = module.hub.module.private_service_connect
}

moved {
  from = module.hub_network.module.hierarchical_firewall_policies
  to   = module.hub.module.hierarchical_firewall_policies
}

moved {
  from = module.hub_network.module.vpc_service_controls
  to   = module.hub.module.vpc_service_controls
}

# Hub Cloud Armor policy (host default-on) -> standalone primitive.
moved {
  from = module.hub_network.module.cloud_armor[0]
  to   = module.hub_cloud_armor
}

# --- DNS anchor network (dns-anchor): network core -> module.dns_anchor.module.network ---

moved {
  from = module.dns_hub_network.terraform_data.deletion_protection_guard
  to   = module.dns_anchor.module.network.terraform_data.deletion_protection_guard
}

moved {
  from = module.dns_hub_network.terraform_data.subnet_cidr_count_guard[0]
  to   = module.dns_anchor.module.network.terraform_data.subnet_cidr_count_guard
}

moved {
  from = module.dns_hub_network.module.vpc[0]
  to   = module.dns_anchor.module.network.module.vpc
}

moved {
  from = module.dns_hub_network.module.public_subnets
  to   = module.dns_anchor.module.network.module.public_subnets
}

moved {
  from = module.dns_hub_network.module.private_subnets
  to   = module.dns_anchor.module.network.module.private_subnets
}

moved {
  from = module.dns_hub_network.module.database_subnets
  to   = module.dns_anchor.module.network.module.database_subnets
}

moved {
  from = module.dns_hub_network.module.firewall_apigateway_to_public[0]
  to   = module.dns_anchor.module.network.module.firewall_apigateway_to_public
}

moved {
  from = module.dns_hub_network.module.firewall_public_to_compute[0]
  to   = module.dns_anchor.module.network.module.firewall_public_to_compute
}

moved {
  from = module.dns_hub_network.module.firewall_compute_to_database[0]
  to   = module.dns_anchor.module.network.module.firewall_compute_to_database
}

moved {
  from = module.dns_hub_network.module.firewall_health_checks[0]
  to   = module.dns_anchor.module.network.module.firewall_health_checks
}

moved {
  from = module.dns_hub_network.module.firewall_database_deny_egress[0]
  to   = module.dns_anchor.module.network.module.firewall_database_deny_egress
}

moved {
  from = module.dns_hub_network.module.firewall_deny_all[0]
  to   = module.dns_anchor.module.network.module.firewall_deny_all
}

moved {
  from = module.dns_hub_network.module.firewall_iap_ssh_rdp
  to   = module.dns_anchor.module.network.module.firewall_iap_ssh_rdp
}

# --- DNS anchor: the root private zone moves into dns-anchor's zone map ---

moved {
  from = module.dns_hub_zone
  to   = module.dns_anchor.module.dns_zones["internal-root"]
}
