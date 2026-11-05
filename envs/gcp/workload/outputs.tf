output "environment" {
  description = "Application environment name"
  value       = var.environment
}

output "host_project_id" {
  description = "The host project ID for this environment"
  value       = local.env_config.host_project_id
}

output "folder_id" {
  description = "Folder ID for this environment"
  value       = local.env_config.folder_id
}

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

output "security_policy_id" {
  description = "Cloud Armor security policy ID (null when Cloud Armor is disabled)"
  value       = module.host.security_policy_id
}

output "vpc_sc_perimeter_names" {
  description = "Map of VPC-SC perimeter key to perimeter name, or null when VPC-SC is disabled. Callers should use try(output.vpc_sc_perimeter_names, null) to handle the null case safely."
  value       = module.host.vpc_service_controls != null ? { for k, v in module.host.vpc_service_controls : k => v.name } : null
}

output "service_team_project_ids" {
  description = "Map of service team name to the created GCP service project ID (empty when no service_teams are declared)."
  value       = { for k, m in module.service_team : k => m.project_id }
}

output "saas_secret_id" {
  description = "Resource ID of the bridged Supabase connection secret in Secret Manager, or null when enable_saas_secret_bridge is false."
  value       = var.enable_saas_secret_bridge ? module.saas_secret_bridge[0].secret_ids[var.saas_secret_name] : null
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
  description = "Name of the env GKE Autopilot cluster, or null when enable_gke_autopilot = false."
  value       = module.app_services.gke_cluster_name
}

output "vm_backup_policy_self_links" {
  description = "Map of target project key (host, team-<name>) to its snapshot-schedule resource policy self_links. Attach these to persistent disks. Empty when enable_vm_backup_policy = false."
  value       = { for k, m in module.vm_backup_policy : k => m.resource_policy_self_links }
}

output "os_patch_deployment_ids" {
  description = "Map of target project key (host, team-<name>) to its VM Manager patch deployment IDs. Empty when enable_os_patch_management = false."
  value       = { for k, m in module.os_patch_management : k => m.patch_deployment_ids }
}
