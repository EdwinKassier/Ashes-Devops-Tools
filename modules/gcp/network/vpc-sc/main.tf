/**
 * Copyright 2023 Ashes
 *
 * VPC Service Controls Module - Main Configuration
 *
 * Creates service perimeters to protect GCP resources from data exfiltration
 * and unauthorized access, even from within Google Cloud.
 */

# -----------------------------------------------------------------------------
# DELETION PROTECTION SENTINEL
# -----------------------------------------------------------------------------
# Terraform's prevent_destroy must be a static literal — it cannot reference
# a variable. A sentinel terraform_data resource carries prevent_destroy = true
# and is created conditionally on var.enable_deletion_protection. Removing the
# sentinel (by setting enable_deletion_protection = false and applying) is also
# blocked, which forces the operator to explicitly acknowledge the intent before
# a second apply can destroy the perimeter.

resource "terraform_data" "deletion_protection" {
  count = var.enable_deletion_protection ? 1 : 0

  input = var.perimeter_name

  lifecycle {
    prevent_destroy = true
  }
}

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

  # SOTA M (dry-run XOR enforced): an ENFORCED perimeter can also carry a staged
  # dry-run `spec` that differs from `status`, so a delta (e.g. extra restricted
  # services) is trialled in dry-run while the current config keeps enforcing.
  # Staging is triggered by any dry_run_* override while enable_dry_run = false.
  stage_dry_run_spec = !var.enable_dry_run && (
    var.dry_run_restricted_services != null ||
    var.dry_run_ingress_policies != null ||
    var.dry_run_egress_policies != null
  )

  # The spec block exists in pure dry-run mode (enable_dry_run) and when staging.
  render_spec = var.enable_dry_run || local.stage_dry_run_spec

  spec_restricted_services = var.dry_run_restricted_services != null ? var.dry_run_restricted_services : var.restricted_services
  spec_ingress_policies    = var.dry_run_ingress_policies != null ? var.dry_run_ingress_policies : var.ingress_policies
  spec_egress_policies     = var.dry_run_egress_policies != null ? var.dry_run_egress_policies : var.egress_policies
}

# -----------------------------------------------------------------------------
# ACCESS LEVELS
# -----------------------------------------------------------------------------

resource "google_access_context_manager_access_level" "levels" {
  for_each = { for level in var.access_levels : level.name => level }

  parent = "accessPolicies/${local.access_policy_name}"
  name   = "accessPolicies/${local.access_policy_name}/accessLevels/${each.key}"
  title  = each.value.title

  description = each.value.description

  basic {
    combining_function = each.value.combining_function

    dynamic "conditions" {
      for_each = each.value.conditions
      content {
        ip_subnetworks         = conditions.value.ip_subnetworks
        required_access_levels = conditions.value.required_access_levels
        members                = conditions.value.members
        negate                 = conditions.value.negate
        regions                = conditions.value.regions

        dynamic "device_policy" {
          for_each = conditions.value.device_policy != null ? [conditions.value.device_policy] : []
          content {
            require_screen_lock              = device_policy.value.require_screen_lock
            require_admin_approval           = device_policy.value.require_admin_approval
            require_corp_owned               = device_policy.value.require_corp_owned
            allowed_encryption_statuses      = device_policy.value.allowed_encryption_statuses
            allowed_device_management_levels = device_policy.value.allowed_device_management_levels

            dynamic "os_constraints" {
              for_each = coalesce(device_policy.value.os_constraints, [])
              content {
                os_type                    = os_constraints.value.os_type
                minimum_version            = os_constraints.value.minimum_version
                require_verified_chrome_os = os_constraints.value.require_verified_chrome_os
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

  # Explicit dry-run spec when in pure dry-run mode OR when an enforced
  # perimeter stages a dry-run delta (dry_run_* overrides).
  use_explicit_dry_run_spec = local.render_spec

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
            identity_type = ingress_policies.value.identity_type
            identities    = ingress_policies.value.identities

            dynamic "sources" {
              for_each = coalesce(ingress_policies.value.sources, [])
              content {
                access_level = sources.value.access_level
                resource     = sources.value.resource
              }
            }
          }

          ingress_to {
            resources = ingress_policies.value.resources

            dynamic "operations" {
              for_each = coalesce(ingress_policies.value.operations, [])
              content {
                service_name = operations.value.service_name

                dynamic "method_selectors" {
                  for_each = coalesce(operations.value.method_selectors, [])
                  content {
                    method     = method_selectors.value.method
                    permission = method_selectors.value.permission
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
            identity_type = egress_policies.value.identity_type
            identities    = egress_policies.value.identities
          }

          egress_to {
            resources = egress_policies.value.resources

            dynamic "operations" {
              for_each = coalesce(egress_policies.value.operations, [])
              content {
                service_name = operations.value.service_name

                dynamic "method_selectors" {
                  for_each = coalesce(operations.value.method_selectors, [])
                  content {
                    method     = method_selectors.value.method
                    permission = method_selectors.value.permission
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  # DRY RUN configuration (spec block). Rendered when dry run is enabled (spec
  # only, nothing enforced) or when an enforced perimeter stages a delta via the
  # dry_run_* overrides (status enforced + spec evaluated in dry-run).
  dynamic "spec" {
    for_each = local.render_spec ? [1] : []
    content {
      resources           = [for p in var.protected_projects : "projects/${p}"]
      restricted_services = local.spec_restricted_services
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
        for_each = local.spec_ingress_policies
        content {
          ingress_from {
            identity_type = ingress_policies.value.identity_type
            identities    = ingress_policies.value.identities

            dynamic "sources" {
              for_each = coalesce(ingress_policies.value.sources, [])
              content {
                access_level = sources.value.access_level
                resource     = sources.value.resource
              }
            }
          }

          ingress_to {
            resources = ingress_policies.value.resources

            dynamic "operations" {
              for_each = coalesce(ingress_policies.value.operations, [])
              content {
                service_name = operations.value.service_name

                dynamic "method_selectors" {
                  for_each = coalesce(operations.value.method_selectors, [])
                  content {
                    method     = method_selectors.value.method
                    permission = method_selectors.value.permission
                  }
                }
              }
            }
          }
        }
      }

      # Egress policies
      dynamic "egress_policies" {
        for_each = local.spec_egress_policies
        content {
          egress_from {
            identity_type = egress_policies.value.identity_type
            identities    = egress_policies.value.identities
          }

          egress_to {
            resources = egress_policies.value.resources

            dynamic "operations" {
              for_each = coalesce(egress_policies.value.operations, [])
              content {
                service_name = operations.value.service_name

                dynamic "method_selectors" {
                  for_each = coalesce(operations.value.method_selectors, [])
                  content {
                    method     = method_selectors.value.method
                    permission = method_selectors.value.permission
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

  lifecycle {
    # Bridge perimeters do not support dry-run mode — the GCP API only accepts a status
    # block (enforced), never a spec block (dry-run). Setting enable_dry_run = true while
    # using a bridge perimeter would silently be ignored (no spec block is generated).
    # Guard explicitly so operators know the combination is not supported.
    precondition {
      condition     = !var.enable_dry_run
      error_message = "Bridge perimeters (PERIMETER_TYPE_BRIDGE) do not support dry-run mode. Set enable_dry_run = false when using perimeter_type = \"PERIMETER_TYPE_BRIDGE\"."
    }
  }
}
