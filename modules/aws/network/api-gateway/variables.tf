# API Gateway (HTTP API / API Gateway v2) primitive for the SRA landing zone.
# The AWS parity counterpart to modules/gcp/network/api-gateway.

# ── Required ──────────────────────────────────────────────────────────────────

variable "name" {
  description = "Name of the API. Used for the aws_apigatewayv2_api name and as the prefix for the access-log group."
  type        = string

  # RE2 caps interval repeats at 1000; 128 is the API Gateway name limit.
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,128}$", var.name))
    error_message = "name must be 1-128 characters and contain only letters, digits, hyphens, and underscores."
  }
}

# ── API ───────────────────────────────────────────────────────────────────────

variable "protocol_type" {
  description = "Protocol for the API. HTTP (HTTP API, the modern default) or WEBSOCKET."
  type        = string
  default     = "HTTP"

  validation {
    condition     = contains(["HTTP", "WEBSOCKET"], var.protocol_type)
    error_message = "protocol_type must be one of: HTTP, WEBSOCKET."
  }
}

variable "description" {
  description = "Human-readable description of the API."
  type        = string
  default     = "Managed by Terraform."
}

variable "cors_configuration" {
  description = <<-EOT
    Optional CORS configuration for the HTTP API. Set to null to disable CORS
    (the default). When set, all fields are optional and map directly onto the
    aws_apigatewayv2_api cors_configuration block.
  EOT
  type = object({
    allow_credentials = optional(bool)
    allow_headers     = optional(list(string))
    allow_methods     = optional(list(string))
    allow_origins     = optional(list(string))
    expose_headers    = optional(list(string))
    max_age           = optional(number)
  })
  default = null
}

# ── Stage ───────────────────────────────────────────────────────────────────

variable "stage_name" {
  description = "Name of the (auto-deployed) stage. Use \"$default\" for the default stage."
  type        = string
  default     = "$default"

  validation {
    condition     = can(regex("^(\\$default|[a-zA-Z0-9_-]{1,128})$", var.stage_name))
    error_message = "stage_name must be \"$default\" or 1-128 characters of letters, digits, hyphens, and underscores."
  }
}

variable "routes" {
  description = <<-EOT
    Routes to create on the API. Each entry produces one aws_apigatewayv2_route
    plus its backing aws_apigatewayv2_integration. Default empty = no routes
    (the API is created bare, for callers that manage routes elsewhere).
      - route_key:          e.g. "GET /items" or "$default"
      - integration_uri:    backend URI (Lambda ARN, HTTP URL, ...)
      - integration_type:   AWS_PROXY | HTTP_PROXY | HTTP | MOCK
      - authorization_type: NONE | AWS_IAM | JWT | CUSTOM (default AWS_IAM — secure by default)
      - authorizer_id:      required when authorization_type is JWT or CUSTOM
  EOT
  type = list(object({
    route_key          = string
    integration_uri    = string
    integration_type   = optional(string, "AWS_PROXY")
    authorization_type = optional(string, "AWS_IAM")
    authorizer_id      = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.routes :
      contains(["AWS_PROXY", "HTTP_PROXY", "HTTP", "MOCK"], r.integration_type)
    ])
    error_message = "each route integration_type must be one of: AWS_PROXY, HTTP_PROXY, HTTP, MOCK."
  }

  validation {
    condition = alltrue([
      for r in var.routes :
      contains(["NONE", "AWS_IAM", "JWT", "CUSTOM"], r.authorization_type)
    ])
    error_message = "each route authorization_type must be one of: NONE, AWS_IAM, JWT, CUSTOM."
  }
}

# ── Access logging ────────────────────────────────────────────────────────────

variable "log_retention_days" {
  description = "Retention, in days, for the access-log CloudWatch log group."
  type        = number
  default     = 365

  validation {
    condition = contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days
    )
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (e.g. 1, 7, 30, 90, 365, 731, 0 for never expire)."
  }
}

variable "kms_key_arn" {
  description = "Optional KMS key ARN for encrypting the access-log group. Empty string uses the default CloudWatch Logs encryption."
  type        = string
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws[a-zA-Z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a valid KMS key ARN (arn:aws:kms:...)."
  }
}

# ── Custom domain (optional) ──────────────────────────────────────────────────

variable "enable_custom_domain" {
  description = "Create a custom domain name and map it to the stage. Requires domain_name and certificate_arn."
  type        = bool
  default     = false

  # Cross-variable validation (Terraform >= 1.9): a custom domain is
  # meaningless without both the domain name and the ACM certificate.
  validation {
    condition     = !var.enable_custom_domain || (var.domain_name != "" && var.certificate_arn != "")
    error_message = "enable_custom_domain requires both domain_name and certificate_arn to be set."
  }
}

variable "domain_name" {
  description = "Custom domain name to attach (e.g. api.example.com). Only used when enable_custom_domain = true."
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the custom domain. Required when enable_custom_domain = true; must be in the API's region for regional HTTP APIs."
  type        = string
  default     = ""

  validation {
    condition     = var.certificate_arn == "" || can(regex("^arn:aws[a-zA-Z-]*:acm:", var.certificate_arn))
    error_message = "certificate_arn must be empty or a valid ACM certificate ARN (arn:aws:acm:...)."
  }
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags applied to all taggable resources this module creates."
  type        = map(string)
  default     = {}
}
