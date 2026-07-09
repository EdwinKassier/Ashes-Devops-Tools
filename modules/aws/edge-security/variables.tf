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
