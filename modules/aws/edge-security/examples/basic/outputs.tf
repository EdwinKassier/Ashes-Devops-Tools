output "distribution_domain_name" {
  description = "Domain name of the CloudFront distribution created by the module."
  value       = module.edge_security.distribution_domain_name
}

output "web_acl_arn" {
  description = "ARN of the CloudFront-scoped WAFv2 Web ACL."
  value       = module.edge_security.web_acl_arn
}
