# Required variables — no defaults, callers must supply these.

variable "name" {
  description = "Name of the load balancer. Also used as the Name tag and the prefix for the managed security group."
  type        = string

  validation {
    # ELB v2 names: 1-32 chars, alphanumeric and hyphens, no leading/trailing
    # hyphen. Kept well under the RE2 1000 interval cap.
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,30}[a-zA-Z0-9])?$", var.name))
    error_message = "name must be 1-32 characters, alphanumeric or hyphens, and must not start or end with a hyphen."
  }
}

variable "vpc_id" {
  description = "ID of the VPC the target groups (and the optional managed security group) live in."
  type        = string

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "vpc_id must be a VPC id beginning with vpc-."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs the load balancer is attached to. Provide at least two subnets in different AZs for production availability."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must contain at least one subnet."
  }
}

# Optional variables — sensible, secure defaults.

variable "load_balancer_type" {
  description = "Load balancer type: 'application' (L7 ALB) or 'network' (L4 NLB)."
  type        = string
  default     = "application"

  validation {
    condition     = contains(["application", "network"], var.load_balancer_type)
    error_message = "load_balancer_type must be either 'application' or 'network'."
  }
}

variable "internal" {
  description = "Whether the load balancer is internal (true, no public IPs) or internet-facing (false)."
  type        = bool
  default     = true
}

variable "security_group_ids" {
  description = "Existing security group IDs to attach to the load balancer. Merged with the module-created group when create_security_group = true."
  type        = list(string)
  default     = []
}

variable "create_security_group" {
  description = "Whether this module creates a security group for the load balancer (typically for an ALB). The caller adds ingress rules via the exported security_group_id."
  type        = bool
  default     = false
}

variable "drop_invalid_header_fields" {
  description = "For application load balancers, drop HTTP headers with invalid fields. Ignored for network load balancers."
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Protect the load balancer from accidental deletion. Defaults to true; set false only for ephemeral/test load balancers."
  type        = bool
  default     = true
}

variable "target_groups" {
  description = <<-EOT
    Target groups to create, keyed by a stable local key referenced from listeners.
    Each entry configures protocol, port, target_type, and an optional health_check.
  EOT
  type = map(object({
    name        = string
    port        = number
    protocol    = string
    target_type = optional(string, "instance")
    health_check = optional(object({
      enabled             = optional(bool, true)
      path                = optional(string, "/")
      port                = optional(string, "traffic-port")
      protocol            = optional(string, "HTTP")
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 3)
      interval            = optional(number, 30)
      timeout             = optional(number, 5)
      matcher             = optional(string, "200")
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for tg in values(var.target_groups) :
      contains(["HTTP", "HTTPS", "TCP", "TLS", "UDP", "TCP_UDP", "GENEVE"], tg.protocol)
    ])
    error_message = "Each target_groups protocol must be one of: HTTP, HTTPS, TCP, TLS, UDP, TCP_UDP, GENEVE."
  }

  validation {
    condition = alltrue([
      for tg in values(var.target_groups) :
      contains(["instance", "ip", "lambda", "alb"], tg.target_type)
    ])
    error_message = "Each target_groups target_type must be one of: instance, ip, lambda, alb."
  }

  validation {
    condition = alltrue([
      for tg in values(var.target_groups) : tg.port >= 1 && tg.port <= 65535
    ])
    error_message = "Each target_groups port must be between 1 and 65535."
  }
}

variable "listeners" {
  description = <<-EOT
    Listeners to create, keyed by a stable local key. Each listener forwards to
    the target group named by target_group_key. Provide certificate_arn (and
    optionally ssl_policy) for TLS-terminating listeners (HTTPS/TLS).
  EOT
  type = map(object({
    port             = number
    protocol         = string
    target_group_key = string
    certificate_arn  = optional(string)
    ssl_policy       = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
  }))
  default = {}

  validation {
    condition = alltrue([
      for l in values(var.listeners) :
      contains(["HTTP", "HTTPS", "TCP", "TLS", "UDP", "TCP_UDP"], l.protocol)
    ])
    error_message = "Each listeners protocol must be one of: HTTP, HTTPS, TCP, TLS, UDP, TCP_UDP."
  }

  validation {
    # TLS-terminating listeners require a certificate.
    condition = alltrue([
      for l in values(var.listeners) :
      contains(["HTTPS", "TLS"], l.protocol) ? l.certificate_arn != null : true
    ])
    error_message = "Listeners with protocol HTTPS or TLS must set certificate_arn."
  }

  validation {
    condition = alltrue([
      for l in values(var.listeners) : l.port >= 1 && l.port <= 65535
    ])
    error_message = "Each listeners port must be between 1 and 65535."
  }
}

variable "access_logs" {
  description = "Optional S3 access logging. Provide bucket (and optional prefix); set enabled=false to configure the destination without turning logging on."
  type = object({
    bucket  = string
    prefix  = optional(string, "")
    enabled = optional(bool, true)
  })
  default = null
}

variable "tags" {
  description = "Tags applied to the load balancer, target groups, listeners, and managed security group."
  type        = map(string)
  default     = {}
}
