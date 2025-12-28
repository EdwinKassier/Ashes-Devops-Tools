# GCP Organization Policy Module
# Dynamically creates organization policies for governance controls

# -----------------------------------------------------------------------------
# Boolean Policies (enforce = true/false)
# Examples: sql.restrictPublicIp, compute.requireShieldedVm
# -----------------------------------------------------------------------------
resource "google_org_policy_policy" "boolean_policies" {
  for_each = { for p in var.boolean_policies : p.constraint => p }

  name   = "${var.parent}/policies/${each.value.constraint}"
  parent = var.parent

  spec {
    rules {
      enforce = each.value.enforce ? "TRUE" : "FALSE"
    }
  }
}

# -----------------------------------------------------------------------------
# List Policies (allow/deny specific values)
# Examples: gcp.resourceLocations, gcp.restrictNonCmekServices
# -----------------------------------------------------------------------------
resource "google_org_policy_policy" "list_policies" {
  for_each = { for p in var.list_policies : p.constraint => p }

  name   = "${var.parent}/policies/${each.value.constraint}"
  parent = var.parent

  spec {
    rules {
      allow_all = each.value.allow_all ? "TRUE" : null
      deny_all  = each.value.deny_all ? "TRUE" : null

      dynamic "values" {
        for_each = length(coalesce(each.value.allowed_values, [])) > 0 || length(coalesce(each.value.denied_values, [])) > 0 ? [1] : []
        content {
          allowed_values = each.value.allowed_values
          denied_values  = each.value.denied_values
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Custom Constraints (Custom Organization Policies)
# -----------------------------------------------------------------------------
resource "google_org_policy_custom_constraint" "custom_constraints" {
  for_each = { for c in var.custom_constraints : c.name => c }

  name         = "${var.parent}/customConstraints/${each.value.name}"
  parent       = var.parent
  display_name = each.value.display_name
  description  = each.value.description
  action_type  = each.value.action_type
  condition    = each.value.condition
  method_types = each.value.method_types
  resource_types = each.value.resource_types
}
