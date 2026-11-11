/**
 * Copyright 2026 Ashes
 *
 * Environment Stage - Outputs (the envs/gcp/workload root outputs, plus
 * `components`).
 */

output "network_id" {
  description = "The VPC network ID"
  value       = module.host.network_id
}

output "network_self_link" {
  description = "The VPC network self-link"
  value       = module.host.network_self_link
}

output "network_name" {
  description = "The VPC network name"
  value       = module.host.network_name
}

output "subnets" {
  description = "All subnet outputs organized by tier"
  value       = module.host.subnets
}

output "nat_ip" {
  description = "The NAT gateway IP addresses"
  value       = module.host.nat_ip
}

output "dns_zones" {
  description = "DNS zone outputs"
  value       = module.host.dns_zones
}

output "vpc_peerings" {
  description = "VPC peering connection outputs"
  value       = module.host.vpc_peerings
}

output "ncc_spoke_id" {
  description = "The environment VPC's NCC spoke ID, or null with hub.connectivity = peering."
  value       = module.host.ncc_spoke_id
}

output "security_policy_id" {
  description = "Cloud Armor security policy ID (null when Cloud Armor is disabled)"
  value       = module.host.security_policy_id
}

output "vpc_sc_perimeter_names" {
  description = "Map of VPC-SC perimeter key to perimeter name, or null when VPC-SC is disabled."
  value       = module.host.vpc_service_controls != null ? { for k, v in module.host.vpc_service_controls : k => v.name } : null
}

output "service_team_project_ids" {
  description = "Map of service team name to the created GCP service project ID (empty when no service_teams are declared)."
  value       = { for k, m in module.service_team : k => m.project_id }
}

output "saas_secret_id" {
  description = "Resource ID of the bridged secret in Secret Manager, or null when saas_secret_bridge.enabled is false."
  value       = var.saas_secret_bridge.enabled ? module.saas_secret_bridge[0].secret_ids[var.saas_secret_bridge.secret_name] : null
}

output "app_services" {
  description = "Per app service: Cloud Run url and name, image_repository, runtime/deploy SA emails, Cloud SQL connection name and IAM DB user (empty when app_services = {})."
  value       = module.app_services.services
}

output "app_deploy_workload_identity_provider" {
  description = "Full resource name of the app-deploy GitHub WIF provider (google-github-actions/auth `workload_identity_provider`), or null when no service declares `github`."
  value       = module.app_services.workload_identity_provider
}

output "app_github_actions" {
  description = "Per service, the GitHub variables the delivery workflow needs: GCP_WIF_PROVIDER, GCP_DEPLOY_SA, GCP_PROJECT_ID, GCP_REGION, CLOUD_RUN_SERVICE, IMAGE_REPOSITORY."
  value       = module.app_services.github_actions
}

output "gke_cluster_name" {
  description = "Name of the env GKE Autopilot cluster, or null when app_platform.gke.enabled = false."
  value       = module.app_services.gke_cluster_name
}

output "vm_backup_policy_self_links" {
  description = "Map of target project key (host, team-<name>) to its snapshot-schedule resource policy self_links. Attach these to persistent disks. Empty when vm_operations.enable_backup_policy = false."
  value       = { for k, m in module.vm_backup_policy : k => m.resource_policy_self_links }
}

output "os_patch_deployment_ids" {
  description = "Map of target project key (host, team-<name>) to its VM Manager patch deployment IDs. Empty when vm_operations.enable_os_patch_management = false."
  value       = { for k, m in module.os_patch_management : k => m.patch_deployment_ids }
}

output "public_ingress" {
  description = "Per exposed app service: the global load balancer IP to point the domains' A records at (unless dns_managed_zone created them), the domains, and the managed certificate ID. Empty when public ingress is off."
  value = {
    for k, m in module.app_ingress : k => {
      ip_address     = m.ip_address
      domains        = m.managed_domains
      certificate_id = m.certificate_id
    }
  }
}

output "components" {
  description = "Plan-time summary of what the environment creates: budget, cloud_armor and saas_secret_bridge (bool), the keys of vpc_sc_perimeters, service_teams, vm_backup_targets, os_patch_targets and public_ingress, the effective psc_target, and host_project_workloads (whether app services without a service_team may run in the host project)."
  value = {
    budget             = length(module.budget) > 0
    cloud_armor        = module.host.cloud_armor != null
    vpc_sc_perimeters  = keys(module.host.vpc_service_controls)
    service_teams      = keys(module.service_team)
    vm_backup_targets  = keys(module.vm_backup_policy)
    os_patch_targets   = keys(module.os_patch_management)
    saas_secret_bridge = length(module.saas_secret_bridge) > 0
    public_ingress     = keys(module.app_ingress)
    psc_target         = local.psc_target
    # Whether app services may run in the Shared VPC host project.
    host_project_workloads = coalesce(var.enable_host_project_workloads, !var.is_production)
  }
}
