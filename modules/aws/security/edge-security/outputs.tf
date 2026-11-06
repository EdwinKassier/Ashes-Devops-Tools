output "web_acl_arn" {
  description = "ARN of the CloudFront-scoped WAFv2 Web ACL, or null when edge is disabled."
  value       = try(aws_wafv2_web_acl.cloudfront[0].arn, null)
}

output "distribution_id" {
  description = "ID of the CloudFront distribution, or null when edge is disabled."
  value       = try(aws_cloudfront_distribution.this[0].id, null)
}

output "distribution_domain_name" {
  description = "Domain name of the CloudFront distribution, or null when edge is disabled."
  value       = try(aws_cloudfront_distribution.this[0].domain_name, null)
}

output "vpc_origin_id" {
  description = "ID of the CloudFront VPC origin, or null when enable_vpc_origin is false."
  value       = try(aws_cloudfront_vpc_origin.this[0].id, null)
}

output "regional_web_acl_arn" {
  description = "ARN of the REGIONAL WAFv2 Web ACL, or null when enable_regional_waf is false."
  value       = try(aws_wafv2_web_acl.regional[0].arn, null)
}
