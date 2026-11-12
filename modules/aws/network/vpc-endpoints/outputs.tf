output "endpoint_ids" {
  description = "Map of interface service name to the created VPC endpoint ID."
  value       = { for svc, ep in aws_vpc_endpoint.interface : svc => ep.id }
}

output "phz_id" {
  description = "Zone ID of the shared private hosted zone, or null when no zone was created."
  value       = try(aws_route53_zone.shared[0].zone_id, null)
}

output "shared_dns_zone_arns" {
  description = "Map of interface service to the ARN of its private hosted zone (enable_shared_private_dns), empty otherwise. Add these to a Route 53 Profile so spoke VPCs resolve the central endpoints."
  value       = { for svc, z in aws_route53_zone.endpoint : svc => z.arn }
}

output "resource_org_scoped_services" {
  description = "Interface services whose module-built endpoint policy also requires an org-owned resource (aws:ResourceOrgID). Empty in the default org_principals mode or with endpoint_policy_json."
  value       = sort([for svc, ep in aws_vpc_endpoint.interface : svc if var.endpoint_policy_json == null && strcontains(ep.policy, "aws:ResourceOrgID")])
}
