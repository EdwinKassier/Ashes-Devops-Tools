# -----------------------------------------------------------------------------
# Edge posture toggle
# -----------------------------------------------------------------------------

variable "enable_edge" {
  description = "Master switch. When false, the module provisions nothing (all resources are count-gated on this)."
  type        = bool
  default     = false
}

variable "name_prefix" {
  description = "Prefix applied to the WAF Web ACL, CloudFront Shield protection, and metric names."
  type        = string
  default     = "edge"

  validation {
    condition     = length(trimspace(var.name_prefix)) > 0
    error_message = "name_prefix must be a non-empty string."
  }
}

# -----------------------------------------------------------------------------
# TLS / custom domain
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Custom domain for the distribution. When set, an ACM certificate (DNS validation, us-east-1) is created and attached; when empty, the default CloudFront certificate is used."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Origin + caching
# -----------------------------------------------------------------------------

variable "origin_domain_name" {
  description = "DNS name of the origin CloudFront fetches from (an ALB, S3 website endpoint, or arbitrary host)."
  type        = string
  default     = "origin.example.com"
}

variable "allowed_methods" {
  description = "HTTP methods the default cache behavior forwards. Default GET/HEAD (static content); an application origin needs [\"DELETE\", \"GET\", \"HEAD\", \"OPTIONS\", \"PATCH\", \"POST\", \"PUT\"]."
  type        = list(string)
  default     = ["GET", "HEAD"]

  validation {
    condition = contains([
      join(",", sort(["GET", "HEAD"])),
      join(",", sort(["GET", "HEAD", "OPTIONS"])),
      join(",", sort(["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"])),
    ], join(",", sort(var.allowed_methods)))
    error_message = "allowed_methods must be one of the CloudFront method sets: [GET, HEAD], [GET, HEAD, OPTIONS] or all seven methods."
  }
}

variable "origin_request_policy_id" {
  description = "ID of the CloudFront origin request policy for the default behavior (which viewer headers, cookies and query strings reach the origin). Null forwards none beyond the cache key. For an application origin use the managed \"AllViewerExceptHostHeader\" policy (b689b0a8-53d0-40ab-baf2-68738e2966ac)."
  type        = string
  default     = null
}

variable "cache_policy_id" {
  description = "ID of the CloudFront cache policy for the default behavior. Defaults to the AWS managed \"CachingOptimized\" policy."
  type        = string
  default     = "658327ea-f89d-4fab-a63d-7e88639e58f6"
}

# -----------------------------------------------------------------------------
# Shield Advanced (cost-gated)
# -----------------------------------------------------------------------------

variable "enable_shield" {
  description = "Enroll the distribution in AWS Shield Advanced. Off by default because Shield Advanced carries a substantial monthly subscription cost."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# WAF logging
# -----------------------------------------------------------------------------

variable "log_destination_arn" {
  description = "ARN of the log destination (Kinesis Data Firehose, CloudWatch log group, or S3 bucket) for WAF Web ACL logs. When empty, WAF logging is not configured."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# CloudFront VPC origin (private ALB/NLB origin)
# -----------------------------------------------------------------------------

variable "enable_vpc_origin" {
  description = "Front a PRIVATE load balancer through a CloudFront VPC origin (aws_cloudfront_vpc_origin) instead of a public custom origin. Requires vpc_origin_arn; origin_domain_name should be the load balancer's DNS name. The origin VPC must have an internet gateway attached."
  type        = bool
  default     = false
}

variable "vpc_origin_arn" {
  description = "ARN of the internal ALB / NLB (or EC2 instance) the VPC origin targets. Required when enable_vpc_origin is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_vpc_origin || can(regex("^arn:aws[a-z-]*:(elasticloadbalancing|ec2):", var.vpc_origin_arn))
    error_message = "vpc_origin_arn must be an ELB or EC2 instance ARN when enable_vpc_origin is true."
  }
}

variable "vpc_origin_http_port" {
  description = "Port CloudFront uses for HTTP to the VPC origin."
  type        = number
  default     = 80
}

variable "vpc_origin_https_port" {
  description = "Port CloudFront uses for HTTPS to the VPC origin."
  type        = number
  default     = 443
}

variable "vpc_origin_protocol_policy" {
  description = "Protocol CloudFront uses to the VPC origin: http-only (default; the hop stays inside the VPC on CloudFront-managed ENIs and TLS terminates at CloudFront), https-only, or match-viewer. https-only requires the origin certificate to match origin_domain_name."
  type        = string
  default     = "http-only"

  validation {
    condition     = contains(["http-only", "https-only", "match-viewer"], var.vpc_origin_protocol_policy)
    error_message = "vpc_origin_protocol_policy must be http-only, https-only or match-viewer."
  }
}

# -----------------------------------------------------------------------------
# Regional WAF (internet-facing ALB without CloudFront)
# -----------------------------------------------------------------------------

variable "enable_regional_waf" {
  description = "Create a REGIONAL WAFv2 Web ACL (AWS Common + KnownBadInputs managed rule groups) in the default provider's region and associate it with regional_waf_resource_arn. Independent of enable_edge."
  type        = bool
  default     = false
}

variable "regional_waf_resource_arn" {
  description = "ARN of the regional resource (ALB, API Gateway stage, AppSync API, Cognito user pool) the regional Web ACL is associated with. Required when enable_regional_waf is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_regional_waf || can(regex("^arn:aws[a-z-]*:", var.regional_waf_resource_arn))
    error_message = "regional_waf_resource_arn must be an ARN when enable_regional_waf is true."
  }
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates (merged after provider default_tags; resource-specific tags such as Name win)."
  type        = map(string)
  default     = {}
  nullable    = false
}
