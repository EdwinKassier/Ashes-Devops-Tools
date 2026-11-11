/**
 * Copyright 2026 Ashes
 *
 * Secure Web Proxy Module - Variables
 */

variable "project_id" {
  description = "Project that hosts the proxy. Secure Web Proxy can only be deployed in a VPC host project, not a Shared VPC service project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID."
  }
}

variable "name" {
  description = "Base name of the gateway. The policy, URL list, subnets and service attachment derive their names from it."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", var.name))
    error_message = "name must be 1-40 characters of lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "region" {
  description = "Region of the proxy. Secure Web Proxy is regional: clients in other regions need global access on their side (PSC endpoint) or a proxy per region."
  type        = string
}

variable "network" {
  description = "VPC network ID the gateway serves, in the form projects/<project>/global/networks/<name>."
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/global/networks/[^/]+$", var.network))
    error_message = "network must be a network ID of the form projects/<project>/global/networks/<name>."
  }
}

variable "subnetwork" {
  description = "Subnetwork ID the gateway address is allocated from, in the form projects/<project>/regions/<region>/subnetworks/<name>. It must be in var.region."
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/regions/[^/]+/subnetworks/[^/]+$", var.subnetwork))
    error_message = "subnetwork must be a subnetwork ID of the form projects/<project>/regions/<region>/subnetworks/<name>."
  }
}

variable "address" {
  description = "Static internal IPv4 address of the gateway inside var.subnetwork. Null (default) lets Google allocate one (read it from the gateway_address output)."
  type        = string
  default     = null
}

variable "ports" {
  description = "Ports the gateway listens on. Clients send HTTP CONNECT (or plain HTTP) to <gateway address>:<port>."
  type        = list(number)
  default     = [443]
  nullable    = false

  validation {
    condition     = length(var.ports) > 0 && alltrue([for p in var.ports : p >= 1 && p <= 65535 && floor(p) == p])
    error_message = "ports must be a non-empty list of whole numbers between 1 and 65535."
  }
}

variable "routing_mode" {
  description = "EXPLICIT_ROUTING_MODE (default): clients use the proxy through HTTP_PROXY / HTTPS_PROXY. NEXT_HOP_ROUTING_MODE: the caller adds routes with the gateway address as next hop, in the same VPC and region. A service attachment needs EXPLICIT_ROUTING_MODE."
  type        = string
  default     = "EXPLICIT_ROUTING_MODE"
  nullable    = false

  validation {
    condition     = contains(["EXPLICIT_ROUTING_MODE", "NEXT_HOP_ROUTING_MODE"], var.routing_mode)
    error_message = "routing_mode must be EXPLICIT_ROUTING_MODE or NEXT_HOP_ROUTING_MODE."
  }
}

variable "certificate_urls" {
  description = "Certificate Manager certificate URLs the gateway presents on TLS connections to the proxy itself. Empty (default) = none."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "allowed_fqdns" {
  description = "Egress allowlist: host names (\"api.example.com\"), wildcard hosts (\"*.example.com\") or host/path patterns the proxy lets through. They become one URL list and one ALLOW rule at priority 1000. Everything that no rule allows is denied. Empty (default) = no allowlist rule, so the proxy denies all traffic unless additional_rules allow some."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for f in var.allowed_fqdns : trimspace(f) != "" && !strcontains(f, "://")])
    error_message = "allowed_fqdns entries must be non-empty host names or host/path patterns without a scheme (no \"https://\")."
  }
}

variable "additional_rules" {
  description = "Extra gateway security policy rules, keyed by rule name: priority (lower wins; 1000 is taken by the allowlist rule), action ALLOW or DENY, a CEL session_matcher (for example \"host() == 'example.com'\" or \"source.matchServiceAccount('sa@project.iam.gserviceaccount.com')\"), an optional CEL application_matcher, description and enabled."
  type = map(object({
    priority            = number
    action              = string
    session_matcher     = string
    application_matcher = optional(string)
    description         = optional(string)
    enabled             = optional(bool, true)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, r in var.additional_rules : can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", k))])
    error_message = "additional_rules keys must be lowercase letters, digits and hyphens, starting with a letter, at most 63 characters."
  }
  validation {
    condition     = alltrue([for r in values(var.additional_rules) : contains(["ALLOW", "DENY"], r.action)])
    error_message = "additional_rules action must be ALLOW or DENY."
  }
  validation {
    condition     = alltrue([for r in values(var.additional_rules) : r.priority >= 0 && r.priority <= 2147483647 && r.priority != 1000])
    error_message = "additional_rules priority must be between 0 and 2147483647 and must not be 1000 (the allowlist rule)."
  }
  validation {
    condition     = length(distinct([for r in values(var.additional_rules) : r.priority])) == length(var.additional_rules)
    error_message = "additional_rules priorities must be unique."
  }
}

variable "create_proxy_only_subnet" {
  description = "Create the regional proxy-only subnet (purpose REGIONAL_MANAGED_PROXY, role ACTIVE) the gateway needs. False (default) = one already exists in the network and region (it is shared with regional Envoy load balancers, and a network can have only one active one per region)."
  type        = bool
  default     = false
  nullable    = false
}

variable "proxy_only_subnet_cidr" {
  description = "CIDR of the proxy-only subnet (Google recommends a /23). Required when create_proxy_only_subnet is true."
  type        = string
  default     = null

  validation {
    condition     = var.proxy_only_subnet_cidr == null || can(cidrnetmask(var.proxy_only_subnet_cidr))
    error_message = "proxy_only_subnet_cidr must be a valid IPv4 CIDR."
  }
  validation {
    condition     = !var.create_proxy_only_subnet || var.proxy_only_subnet_cidr != null
    error_message = "proxy_only_subnet_cidr is required when create_proxy_only_subnet is true."
  }
}

variable "create_service_attachment" {
  description = "Publish the gateway through a Private Service Connect service attachment, so other VPC networks (for example environment spokes) reach it through a PSC endpoint in their own VPC. Needs EXPLICIT_ROUTING_MODE, psc_nat_subnet_cidr and consumer_accept_projects. Default false."
  type        = bool
  default     = false
  nullable    = false

  validation {
    condition     = !var.create_service_attachment || var.routing_mode == "EXPLICIT_ROUTING_MODE"
    error_message = "create_service_attachment needs routing_mode = EXPLICIT_ROUTING_MODE (PSC publishing does not support next-hop mode)."
  }
}

variable "psc_nat_subnet_cidr" {
  description = "CIDR of the Private Service Connect NAT subnet (purpose PRIVATE_SERVICE_CONNECT) the service attachment source-NATs consumer traffic into. Required when create_service_attachment is true. Policy rules cannot match on the original client IP through PSC."
  type        = string
  default     = null

  validation {
    condition     = var.psc_nat_subnet_cidr == null || can(cidrnetmask(var.psc_nat_subnet_cidr))
    error_message = "psc_nat_subnet_cidr must be a valid IPv4 CIDR."
  }
  validation {
    condition     = !var.create_service_attachment || var.psc_nat_subnet_cidr != null
    error_message = "psc_nat_subnet_cidr is required when create_service_attachment is true."
  }
}

variable "consumer_accept_projects" {
  description = "Project IDs or numbers whose PSC endpoints the service attachment accepts (ACCEPT_MANUAL). Only these projects can send traffic through the proxy. Required (non-empty) when create_service_attachment is true."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = !var.create_service_attachment || length(var.consumer_accept_projects) > 0
    error_message = "consumer_accept_projects must list at least one project when create_service_attachment is true (the attachment accepts listed projects only)."
  }
}

variable "consumer_connection_limit" {
  description = "Maximum PSC endpoints each accepted project may connect."
  type        = number
  default     = 10
  nullable    = false

  validation {
    condition     = var.consumer_connection_limit >= 1
    error_message = "consumer_connection_limit must be at least 1."
  }
}

variable "labels" {
  description = "Labels applied to the gateway."
  type        = map(string)
  default     = {}
  nullable    = false
}
