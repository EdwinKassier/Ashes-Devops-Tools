/**
 * Copyright 2023 Ashes
 *
 * VPC Service Controls Module - Main Configuration
 * 
 * Creates service perimeters to protect GCP resources from data exfiltration
 * and unauthorized access, even from within Google Cloud.
 */

# -----------------------------------------------------------------------------
# ACCESS POLICY (if not provided)
# -----------------------------------------------------------------------------

resource "google_access_context_manager_access_policy" "policy" {
  count = var.create_access_policy ? 1 : 0

  parent = var.organization_id
  title  = var.access_policy_title
}

locals {
  access_policy_name = var.create_access_policy ? google_access_context_manager_access_policy.policy[0].name : var.access_policy_name
}

# -----------------------------------------------------------------------------
# ACCESS LEVELS
# -----------------------------------------------------------------------------

resource "google_access_context_manager_access_level" "levels" {
  for_each = { for level in var.access_levels : level.name => level }

  parent = "accessPolicies/${local.access_policy_name}"
  name   = "accessPolicies/${local.access_policy_name}/accessLevels/${each.key}"
  title  = each.value.title

  description = try(each.value.description, null)

  basic {
    combining_function = try(each.value.combining_function, "AND")

    dynamic "conditions" {
      for_each = each.value.conditions
      content {
        ip_subnetworks         = try(conditions.value.ip_subnetworks, null)
        required_access_levels = try(conditions.value.required_access_levels, null)
        members                = try(conditions.value.members, null)
        negate                 = try(conditions.value.negate, false)
        regions                = try(conditions.value.regions, null)

        dynamic "device_policy" {
          for_each = try(conditions.value.device_policy, null) != null ? [conditions.value.device_policy] : []
          content {
            require_screen_lock              = try(device_policy.value.require_screen_lock, null)
            require_admin_approval           = try(device_policy.value.require_admin_approval, null)
            require_corp_owned               = try(device_policy.value.require_corp_owned, null)
            allowed_encryption_statuses      = try(device_policy.value.allowed_encryption_statuses, null)
            allowed_device_management_levels = try(device_policy.value.allowed_device_management_levels, null)

            dynamic "os_constraints" {
              for_each = try(device_policy.value.os_constraints, [])
              content {
                os_type                    = os_constraints.value.os_type
                minimum_version            = try(os_constraints.value.minimum_version, null)
                require_verified_chrome_os = try(os_constraints.value.require_verified_chrome_os, null)
              }
            }
          }
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# SERVICE PERIMETER (Regular)
# -----------------------------------------------------------------------------

resource "google_access_context_manager_service_perimeter" "perimeter" {
  count = var.perimeter_type == "PERIMETER_TYPE_REGULAR" ? 1 : 0

  parent         = "accessPolicies/${local.access_policy_name}"
  name           = "accessPolicies/${local.access_policy_name}/servicePerimeters/${var.perimeter_name}"
  title          = var.perimeter_title
  description    = var.description
  perimeter_type = "PERIMETER_TYPE_REGULAR"

  # Use explicit dry run spec when dry run is enabled
  use_explicit_dry_run_spec = var.enable_dry_run

  # ENFORCED configuration (always defined for active perimeters)
  dynamic "status" {
    for_each = var.enable_dry_run ? [] : [1]
    content {
      resources           = [for p in var.protected_projects : "projects/${p}"]
      restricted_services = var.restricted_services
      access_levels = [
        for level in var.access_levels :
        "accessPolicies/${local.access_policy_name}/accessLevels/${level.name}"
      ]

      # VPC accessible services
      dynamic "vpc_accessible_services" {
        for_each = var.vpc_accessible_services != null ? [var.vpc_accessible_services] : []
        content {
          enable_restriction = vpc_accessible_services.value.enable_restriction
          allowed_services   = vpc_accessible_services.value.allowed_services
        }
      }

      # Ingress policies
      dynamic "ingress_policies" {
        for_each = var.ingress_policies
        content {
          ingress_from {
            identity_type = try(ingress_policies.value.identity_type, null)
            identities    = try(ingress_policies.value.identities, null)

            dynamic "sources" {
              for_each = try(ingress_policies.value.sources, [])
              content {
                access_level = try(sources.value.access_level, null)
                resource     = try(sources.value.resource, null)
              }
            }
          }

          ingress_to {
            resources = try(ingress_policies.value.resources, ["*"])

            dynamic "operations" {
              for_each = try(ingress_policies.value.operations, [])
              content {
                service_name = operations.value.service_name

                dynamic "method_selectors" {
                  for_each = try(operations.value.method_selectors, [])
                  content {
                    method     = try(method_selectors.value.method, null)
                    permission = try(method_selectors.value.permission, null)
                  }
                }
              }
            }
          }
        }
      }

      # Egress policies
      dynamic "egress_policies" {
        for_each = var.egress_policies
        content {
          egress_from {
            identity_type = try(egress_policies.value.identity_type, null)
            identities    = try(egress_policies.value.identities, null)
          }

          egress_to {
            resources = try(egress_policies.value.resources, null)

            dynamic "operations" {
              for_each = try(egress_policies.value.operations, [])
              content {
                service_name = operations.value.service_name

                dynamic "method_selectors" {
                  for_each = try(operations.value.method_selectors, [])
                  content {
                    method     = try(method_selectors.value.method, null)
                    permission = try(method_selectors.value.permission, null)
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  # DRY RUN configuration (spec block - used when dry run is enabled)
  dynamic "spec" {
    for_each = var.enable_dry_run ? [1] : []
    content {
      resources           = [for p in var.protected_projects : "projects/${p}"]
      restricted_services = var.restricted_services
      access_levels = [
        for level in var.access_levels :
        "accessPolicies/${local.access_policy_name}/accessLevels/${level.name}"
      ]

      # VPC accessible services
      dynamic "vpc_accessible_services" {
        for_each = var.vpc_accessible_services != null ? [var.vpc_accessible_services] : []
        content {
          enable_restriction = vpc_accessible_services.value.enable_restriction
          allowed_services   = vpc_accessible_services.value.allowed_services
        }
      }

      # Ingress policies
      dynamic "ingress_policies" {
        for_each = var.ingress_policies
        content {
          ingress_from {
            identity_type = try(ingress_policies.value.identity_type, null)
            identities    = try(ingress_policies.value.identities, null)

            dynamic "sources" {
              for_each = try(ingress_policies.value.sources, [])
              content {
                access_level = try(sources.value.access_level, null)
                resource     = try(sources.value.resource, null)
              }
            }
          }

          ingress_to {
            resources = try(ingress_policies.value.resources, ["*"])

            dynamic "operations" {
              for_each = try(ingress_policies.value.operations, [])
              content {
                service_name = operations.value.service_name

                dynamic "method_selectors" {
                  for_each = try(operations.value.method_selectors, [])
                  content {
                    method     = try(method_selectors.value.method, null)
                    permission = try(method_selectors.value.permission, null)
                  }
                }
              }
            }
          }
        }
      }

      # Egress policies
      dynamic "egress_policies" {
        for_each = var.egress_policies
        content {
          egress_from {
            identity_type = try(egress_policies.value.identity_type, null)
            identities    = try(egress_policies.value.identities, null)
          }

          egress_to {
            resources = try(egress_policies.value.resources, null)

            dynamic "operations" {
              for_each = try(egress_policies.value.operations, [])
              content {
                service_name = operations.value.service_name

                dynamic "method_selectors" {
                  for_each = try(operations.value.method_selectors, [])
                  content {
                    method     = try(method_selectors.value.method, null)
                    permission = try(method_selectors.value.permission, null)
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [google_access_context_manager_access_level.levels]
}

# -----------------------------------------------------------------------------
# SERVICE PERIMETER (Bridge - for connecting perimeters)
# -----------------------------------------------------------------------------

resource "google_access_context_manager_service_perimeter" "bridge" {
  count = var.perimeter_type == "PERIMETER_TYPE_BRIDGE" ? 1 : 0

  parent         = "accessPolicies/${local.access_policy_name}"
  name           = "accessPolicies/${local.access_policy_name}/servicePerimeters/${var.perimeter_name}"
  title          = var.perimeter_title
  description    = var.description
  perimeter_type = "PERIMETER_TYPE_BRIDGE"

  status {
    resources = [for p in var.protected_projects : "projects/${p}"]
  }
}
