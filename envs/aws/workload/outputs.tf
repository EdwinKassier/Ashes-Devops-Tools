# Workload root outputs. Consumed for cross-account references and operator
# convenience; not a stable cross-root contract like the network root's.

output "vpc_id" {
  description = "The ID of the workload spoke VPC."
  value       = module.aws_workload.vpc_id
}

output "tgw_attachment_id" {
  description = "ID of the spoke VPC's transit-gateway attachment (null without a hub). Add it to aws.network.spoke_attachments.<env> in config/landing-zone.yaml so aws-network accepts it and wires its routing."
  value       = module.aws_workload.tgw_attachment_id
}

output "workload_role_arns" {
  description = "Map of workload IAM role name to role ARN."
  value       = module.aws_workload.workload_role_arns
}

output "saas_secret_arn" {
  description = "ARN of the bridged Supabase connection secret in Secrets Manager, or null when enable_saas_secret_bridge is false. Point the ECS task definition's container secret valueFrom at this ARN."
  value       = var.enable_saas_secret_bridge ? aws_secretsmanager_secret.saas_bridge[0].arn : null
}

# -----------------------------------------------------------------------------
# App services (golden path) — the per-service CI contract
# -----------------------------------------------------------------------------

output "app_services" {
  description = "Per-service deployment contract (ECR repo URL, deploy role ARN, ECS cluster/service, task-definition family, container name, runtime roles, log group, optional database endpoint/secret). Feed these into the service repo's GitHub Actions variables. Empty map when services = {}."
  value       = module.app_services.services
}

output "app_ingress_mode" {
  description = "Effective app ingress mode: internal, public_alb or cloudfront_vpc_origin."
  value       = local.app_ingress_mode
}

output "app_endpoint" {
  description = "Base URL of the shared app entry point, or null when services = {}: https://<CloudFront domain> (cloudfront_vpc_origin), https://<ALB DNS> (public_alb), else the internal ALB URL (https when app_alb_certificate_arn is set)."
  value = !local.apps_enabled ? null : (
    local.app_vpc_origin ? "https://${coalesce(var.app_edge_domain_name, module.app_edge[0].distribution_domain_name)}" :
    "${var.app_alb_certificate_arn != null ? "https" : "http"}://${module.app_services.alb_dns_name}"
  )
}

output "app_edge_distribution_id" {
  description = "CloudFront distribution ID in front of the ALB (cloudfront_vpc_origin), or null."
  value       = try(module.app_edge[0].distribution_id, null)
}

output "app_regional_web_acl_arn" {
  description = "Regional WAF Web ACL associated with the internet-facing ALB (public_alb with enable_app_waf), or null."
  value       = try(module.app_edge[0].regional_web_acl_arn, null)
}

output "workload_kms_key_arn" {
  description = "ARN of the CMK this workload uses (created here as alias/workload-<environment> unless kms_key_arn was supplied)."
  value       = local.kms_key_arn
}

output "app_alb_dns_name" {
  description = "DNS name of the shared per-environment ALB (internal by default), or null when services = {}."
  value       = module.app_services.alb_dns_name
}

output "app_alb_zone_id" {
  description = "Route 53 hosted zone ID of the shared ALB, for alias records, or null when services = {}."
  value       = module.app_services.alb_zone_id
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider in this workload account, or null when enable_github_oidc is false."
  value       = module.app_services.github_oidc_provider_arn
}

output "github_oidc_subjects" {
  description = "Map of service name to the exact OIDC sub claim its deploy role trusts (the GitHub environment / ref the deploy job must run in)."
  value       = module.app_services.github_oidc_subjects
}
