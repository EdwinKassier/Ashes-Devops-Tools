# Host stage (DNS) inputs. Part of modules/gcp/stages/host.

# =============================================================================
# DNS CONFIGURATION
# =============================================================================

variable "dns_zones" {
  description = "Map of DNS zones to create"
  type = map(object({
    dns_name        = string
    visibility      = string
    description     = optional(string)
    dnssec_enabled  = optional(bool, false)
    peering_network = optional(string)
    records = optional(list(object({
      name    = string
      type    = string
      ttl     = number
      rrdatas = list(string)
    })), [])
  }))
  default = {}
}

