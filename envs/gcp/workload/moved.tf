# State migration: module "host" source stages/host -> stages/net-spoke.
#
# The module label is unchanged, so every service-level address (NAT, PSA,
# PSC, Cloud Armor, peering, DNS, flow-log export, VPC-SC, Shared VPC service
# projects, additional firewall rules) keeps its exact address inside
# module.host. Only the network core moved: it now lives in the shared
# network/tiered-vpc building block (module.host.module.network), where the
# always-on resources are no longer count-gated ([0] -> bare address).
#
# The module.host.* moves below chain into the module.host move further down
# (module "environment"): Terraform applies the nested move first, then the
# module move, so a state from before either refactor still lands on
# module.environment.module.host.module.network.* with no destroy/create.
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

# State migration: the inline environment composition -> module "environment"
# (modules/gcp/stages/environment). One move per former root-level module call
# or resource; every address inside them keeps its relative path. Data sources
# need no move. terraform_data.projects_contract_guard stays in this root.

moved {
  from = module.host
  to   = module.environment.module.host
}

moved {
  from = module.budget
  to   = module.environment.module.budget
}

moved {
  from = module.service_team
  to   = module.environment.module.service_team
}

moved {
  from = module.vm_backup_policy
  to   = module.environment.module.vm_backup_policy
}

moved {
  from = google_project_service.osconfig
  to   = module.environment.google_project_service.osconfig
}

moved {
  from = module.os_patch_management
  to   = module.environment.module.os_patch_management
}

moved {
  from = module.saas_secret_bridge
  to   = module.environment.module.saas_secret_bridge
}

moved {
  from = module.app_services
  to   = module.environment.module.app_services
}

moved {
  from = module.app_ingress
  to   = module.environment.module.app_ingress
}
