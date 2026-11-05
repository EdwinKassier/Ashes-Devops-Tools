# Host stage (governance) inputs. Part of modules/gcp/stages/host.

# =============================================================================
# SHARED VPC SERVICE PROJECT CONFIGURATION
# =============================================================================

variable "shared_vpc_service_projects" {
  description = "Map of service projects to attach to this host project (requires enable_shared_vpc_host = true)"
  type = map(object({
    deletion_policy = optional(string, "ABANDON")
    subnet_iam_bindings = optional(list(object({
      subnet = string
      region = string
      member = string
    })), [])
    grant_network_user_to_all_subnets = optional(bool, false)
    network_user_members              = optional(list(string), [])
    network_viewer_members            = optional(list(string), [])
    enable_gke_permissions            = optional(bool, false)
  }))
  default = {}
}

# =============================================================================
# VPC SERVICE CONTROLS CONFIGURATION
# =============================================================================

variable "vpc_service_controls" {
  description = "Map of VPC Service Controls perimeters to create"
  type = map(object({
    # organization_id must be the FULL resource form 'organizations/<numeric-id>'
    # (Access Context Manager's access-policy parent requires this form). NOTE:
    # this diverges from every other org-id input in the repo (governance/tags,
    # governance/cloud-audit-logs, stages/organization var.org_id) which take the
    # BARE numeric id. envs/gcp/workload prefixes the bare org_id output here accordingly.
    # See docs: the vpc-sc module is the sole outlier; a future normalization
    # would have vpc-sc accept the bare id and prefix internally.
    organization_id      = string
    access_policy_name   = optional(string)
    create_access_policy = optional(bool, false)
    perimeter_title      = string
    description          = optional(string, "Managed by Terraform")
    perimeter_type       = optional(string, "PERIMETER_TYPE_REGULAR")
    protected_projects   = optional(list(string), [])
    restricted_services  = optional(list(string), [])
    access_levels = optional(list(object({
      name               = string
      title              = string
      description        = optional(string)
      combining_function = optional(string, "AND")
      conditions = list(object({
        ip_subnetworks = optional(list(string))
        members        = optional(list(string))
        negate         = optional(bool, false)
        regions        = optional(list(string))
      }))
    })), [])
    ingress_policies = optional(list(object({
      identity_type = optional(string)
      identities    = optional(list(string))
      sources = optional(list(object({
        access_level = optional(string)
        resource     = optional(string)
      })))
      resources = optional(list(string))
      operations = optional(list(object({
        service_name = string
        method_selectors = optional(list(object({
          method     = optional(string)
          permission = optional(string)
        })))
      })))
    })), [])
    egress_policies = optional(list(object({
      identity_type = optional(string)
      identities    = optional(list(string))
      resources     = optional(list(string))
      operations = optional(list(object({
        service_name = string
        method_selectors = optional(list(object({
          method     = optional(string)
          permission = optional(string)
        })))
      })))
    })), [])
    enable_dry_run             = optional(bool, true)
    enable_deletion_protection = optional(bool, true)
  }))
  default = {}
}

