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
  value       = module.environment.network_id
}

output "network_self_link" {
  description = "The VPC network self-link"
  value       = module.environment.network_self_link
}

output "network_name" {
  description = "The VPC network name"
  value       = module.environment.network_name
}

output "subnets" {
  description = "All subnet outputs organized by tier"
  value       = module.environment.subnets
}

output "nat_ip" {
  description = "The NAT gateway IP addresses"
  value       = module.environment.nat_ip
}

output "dns_zones" {
  description = "DNS zone outputs"
  value       = module.environment.dns_zones
}

output "vpc_peerings" {
  description = "VPC peering connection outputs"
  value       = module.environment.vpc_peerings
}

output "ncc_spoke_id" {
  description = "The environment VPC's NCC spoke ID, or null with network_connectivity = peering."
  value       = module.environment.ncc_spoke_id
}

output "security_policy_id" {
  description = "Cloud Armor security policy ID (null when Cloud Armor is disabled)"
  value       = module.environment.security_policy_id
}

output "vpc_sc_perimeter_names" {
  description = "Map of VPC-SC perimeter key to perimeter name, or null when VPC-SC is disabled. Callers should use try(output.vpc_sc_perimeter_names, null) to handle the null case safely."
  value       = module.environment.vpc_sc_perimeter_names
}

output "service_team_project_ids" {
  description = "Map of service team name to the created GCP service project ID (empty when no service_teams are declared)."
  value       = module.environment.service_team_project_ids
}

output "saas_secret_id" {
  description = "Resource ID of the bridged Supabase connection secret in Secret Manager, or null when enable_saas_secret_bridge is false."
  value       = module.environment.saas_secret_id
}

output "app_services" {
  description = "Per app service: Cloud Run url and name, image_repository, runtime/deploy SA emails, Cloud SQL connection name and IAM DB user (empty when app_services = {})."
  value       = module.environment.app_services
}

output "app_deploy_workload_identity_provider" {
  description = "Full resource name of the app-deploy GitHub WIF provider (google-github-actions/auth `workload_identity_provider`), or null when no service declares `github`."
  value       = module.environment.app_deploy_workload_identity_provider
}

output "app_github_actions" {
  description = "Per service, the GitHub variables the delivery workflow needs: GCP_WIF_PROVIDER, GCP_DEPLOY_SA, GCP_PROJECT_ID, GCP_REGION, CLOUD_RUN_SERVICE, IMAGE_REPOSITORY."
  value       = module.environment.app_github_actions
}

output "gke_cluster_name" {
  description = "Name of the env GKE Autopilot cluster, or null when enable_gke_autopilot = false."
  value       = module.environment.gke_cluster_name
}

output "vm_backup_policy_self_links" {
  description = "Map of target project key (host, team-<name>) to its snapshot-schedule resource policy self_links. Attach these to persistent disks. Empty when enable_vm_backup_policy = false."
  value       = module.environment.vm_backup_policy_self_links
}

output "os_patch_deployment_ids" {
  description = "Map of target project key (host, team-<name>) to its VM Manager patch deployment IDs. Empty when enable_os_patch_management = false."
  value       = module.environment.os_patch_deployment_ids
}

output "public_ingress" {
  description = "Per exposed app service: the global load balancer IP to point the domains' A records at (unless dns_managed_zone created them), the domains, and the managed certificate ID. Empty when public ingress is off."
  value       = module.environment.public_ingress
}
