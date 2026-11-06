# GCP Organization Policy Module
# Dynamically creates organization policies for governance controls
#
# Managed constraints (constraints/<service>.managed.*) are Google's successors
# to many legacy boolean/list constraints: they support dry-run, parameters and
# Policy Simulator, and are the only versions that receive new features. With
# prefer_managed_constraints = true (default) every legacy constraint that has a
# like-for-like managed equivalent (local.managed_equivalents, verified against
# the Google constraint reference) is set through its managed version instead.
# Constraints with no managed equivalent (or whose managed successor has
# different semantics, e.g. iam.allowedPolicyMemberDomains vs
# iam.managed.allowedPolicyMembers) stay legacy.
locals {
  managed_equivalents = {
    "iam.disableServiceAccountKeyCreation"            = "iam.managed.disableServiceAccountKeyCreation"
    "iam.disableServiceAccountKeyUpload"              = "iam.managed.disableServiceAccountKeyUpload"
    "iam.automaticIamGrantsForDefaultServiceAccounts" = "iam.managed.preventPrivilegedBasicRolesForDefaultServiceAccounts"
    "compute.disableSerialPortAccess"                 = "compute.managed.disableSerialPortAccess"
    "compute.requireOsLogin"                          = "compute.managed.requireOsLogin"
    "compute.disableNestedVirtualization"             = "compute.managed.disableNestedVirtualization"
    "compute.disableGuestAttributesAccess"            = "compute.managed.disableGuestAttributesAccess"
    "sql.restrictPublicIp"                            = "sql.managed.restrictPublicIp"
  }

  # List constraints whose deny_all form maps to an enforced managed boolean.
  managed_list_equivalents = {
    "compute.vmExternalIpAccess" = "compute.managed.vmExternalIpAccess"
  }

  translated_boolean = [
    for p in var.boolean_policies : {
      constraint = local.managed_equivalents[p.constraint]
      enforce    = p.enforce
      parameters = null
    } if var.prefer_managed_constraints && contains(keys(local.managed_equivalents), p.constraint)
  ]
  translated_list = [
    for p in var.list_policies : {
      constraint = local.managed_list_equivalents[p.constraint]
      enforce    = true
      parameters = null
    } if var.prefer_managed_constraints && contains(keys(local.managed_list_equivalents), p.constraint) && p.deny_all
  ]

  effective_boolean_policies = [
    for p in var.boolean_policies : p
    if !(var.prefer_managed_constraints && contains(keys(local.managed_equivalents), p.constraint))
  ]
  effective_list_policies = [
    for p in var.list_policies : p
    if !(var.prefer_managed_constraints && contains(keys(local.managed_list_equivalents), p.constraint) && p.deny_all)
  ]
  effective_managed_policies = concat(local.translated_boolean, local.translated_list, [
    for p in var.managed_policies : { constraint = p.constraint, enforce = p.enforce, parameters = p.parameters }
  ])
}

# -----------------------------------------------------------------------------
# Boolean Policies (enforce = true/false)
# Examples: sql.restrictPublicIp, compute.requireShieldedVm
# -----------------------------------------------------------------------------
resource "google_org_policy_policy" "boolean_policies" {
  for_each = { for p in local.effective_boolean_policies : p.constraint => p }

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
  for_each = { for p in local.effective_list_policies : p.constraint => p }

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
# Managed Constraints (constraints/<service>.managed.*)
# Translated legacy constraints (prefer_managed_constraints) plus explicit
# var.managed_policies, which may carry constraint parameters (JSON).
# -----------------------------------------------------------------------------
resource "google_org_policy_policy" "managed_policies" {
  for_each = { for p in local.effective_managed_policies : p.constraint => p }

  name   = "${var.parent}/policies/${each.value.constraint}"
  parent = var.parent

  spec {
    rules {
      enforce    = each.value.enforce ? "TRUE" : "FALSE"
      parameters = each.value.parameters
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.effective_managed_policies) == length(distinct([for p in local.effective_managed_policies : p.constraint]))
      error_message = "A managed constraint is set twice: once through prefer_managed_constraints (translated from a legacy constraint) and once in managed_policies. Remove one of them."
    }
  }
}

# -----------------------------------------------------------------------------
# Custom Constraints (Custom Organization Policies)
# -----------------------------------------------------------------------------
resource "google_org_policy_custom_constraint" "custom_constraints" {
  for_each = { for c in var.custom_constraints : c.name => c }

  # The `name` field accepts only the short constraint name (e.g. "custom.disableGkeAutoUpgrade").
  # The parent field supplies the org path prefix. Combining them would produce a double-path
  # that the GCP API rejects.
  name           = each.value.name
  parent         = var.parent
  display_name   = each.value.display_name
  description    = each.value.description
  action_type    = each.value.action_type
  condition      = each.value.condition
  method_types   = each.value.method_types
  resource_types = each.value.resource_types

  lifecycle {
    # Custom constraints are organization-level-only resources. The GCP API rejects
    # creation under a folder or project parent with a non-obvious error. Guard early.
    precondition {
      condition     = startswith(var.parent, "organizations/")
      error_message = "Custom org policy constraints can only be created at the organization level. Set parent to 'organizations/<ORG_ID>' (e.g., 'organizations/123456789')."
    }
  }
}

# A custom constraint has no effect until a policy enforces it. Without this
# resource every custom constraint above was defined but inert.
resource "google_org_policy_policy" "custom_constraints" {
  for_each = { for c in var.custom_constraints : c.name => c if c.enforcement != "off" }

  name   = "${var.parent}/policies/${each.key}"
  parent = var.parent

  dynamic "spec" {
    for_each = each.value.enforcement == "enforce" ? [1] : []
    content {
      rules {
        enforce = "TRUE"
      }
    }
  }

  dynamic "dry_run_spec" {
    for_each = each.value.enforcement == "dry_run" ? [1] : []
    content {
      rules {
        enforce = "TRUE"
      }
    }
  }

  depends_on = [google_org_policy_custom_constraint.custom_constraints]
}
