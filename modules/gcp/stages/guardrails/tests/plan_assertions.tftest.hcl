# Behaviour assertions for the stages/guardrails module: the admin-containment
# deny policy (org-wide + tag-scoped audit-store rules), user iam_deny_policies,
# the gcloud spec output for the break-glass path and the render-only mode the
# organization stage uses in its legacy guardrail_owner_mode = "organization".
# mock_provider only — no GCP credentials needed.

mock_provider "google" {}

variables {
  org_id                        = "123456789"
  enable_admin_containment      = true
  containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
  containment_tag_key_id        = "tagKeys/111"
  containment_tag_value_id      = "tagValues/222"
}

run "inert_by_default" {
  command = plan

  variables {
    enable_admin_containment      = false
    containment_exempt_principals = []
    containment_tag_key_id        = null
    containment_tag_value_id      = null
  }

  assert {
    condition     = length(output.deny_policies) == 0 && length(output.deny_policy_names) == 0 && length(output.deny_policy_specs) == 0 && length(output.admin_containment_rules) == 0
    error_message = "with containment off and no iam_deny_policies the stage must plan nothing."
  }
}

run "containment_denies_mutation_and_tag_scopes_audit_store" {
  command = plan

  assert {
    condition     = jsonencode(output.deny_policy_names) == jsonencode(["contain-admin-identity"])
    error_message = "the containment deny policy must be created at the org node."
  }

  assert {
    condition     = jsonencode(module.iam_deny.deny_policy_names) == jsonencode(["contain-admin-identity"]) && output.parent == "cloudresourcemanager.googleapis.com%2Forganizations%2F123456789"
    error_message = "the deny policy must attach to the URL-encoded org node."
  }

  assert {
    condition = length(output.admin_containment_rules) == 2 && alltrue([
      for p in [
        "logging.googleapis.com/sinks.update",
        "logging.googleapis.com/sinks.delete",
        "logging.googleapis.com/exclusions.create",
        "logging.googleapis.com/exclusions.update",
        "logging.googleapis.com/exclusions.delete",
        "logging.googleapis.com/buckets.delete",
        "accesscontextmanager.googleapis.com/servicePerimeters.update",
        "accesscontextmanager.googleapis.com/servicePerimeters.delete",
        "accesscontextmanager.googleapis.com/policies.delete",
        "accesscontextmanager.googleapis.com/accessLevels.update",
        "accesscontextmanager.googleapis.com/accessLevels.delete",
        "accesscontextmanager.googleapis.com/accessLevels.replaceAll",
        "accesscontextmanager.googleapis.com/policies.setIamPolicy",
      ] : contains(output.admin_containment_rules[0].denied_permissions, p)
    ]) && !output.admin_containment_rules[0].tag_scoped
    error_message = "rule 1 must deny sink/exclusion/perimeter mutation org-wide (unconditioned)."
  }

  assert {
    condition = alltrue([
      for p in [
        "storage.googleapis.com/buckets.delete",
        "storage.googleapis.com/buckets.setIamPolicy",
        "storage.googleapis.com/buckets.deleteTagBinding",
        "storage.googleapis.com/buckets.update",
        "storage.googleapis.com/objects.delete",
        "cloudkms.googleapis.com/cryptoKeyVersions.destroy",
        "cloudkms.googleapis.com/cryptoKeyVersions.update",
        "cloudkms.googleapis.com/cryptoKeys.setIamPolicy",
        "cloudkms.googleapis.com/keyRings.setIamPolicy",
        "logging.googleapis.com/buckets.update",
        "logging.googleapis.com/buckets.deleteTagBinding",
      ] : contains(output.admin_containment_rules[1].denied_permissions, p)
    ]) && output.admin_containment_rules[1].tag_scoped
    error_message = "rule 2 must deny audit-store bucket/object/key destruction, scoped by the containment tag."
  }

  assert {
    condition = alltrue([
      for r in output.admin_containment_rules :
      jsonencode(r.exception_principals) == jsonencode(["principalSet://goog/group/break-glass@acme.io"])
    ])
    error_message = "every containment rule must exempt exactly the break-glass principal."
  }

  # Unsupported in IAM deny: they would fail the API call.
  assert {
    condition = !anytrue([
      for r in output.admin_containment_rules : anytrue([
        for p in r.denied_permissions : can(regex("denypolicies|accessPolicies", p))
      ])
    ])
    error_message = "iam.denypolicies.* and accessPolicies.delete are not deny-supported and must not be listed."
  }

  assert {
    condition     = !contains(output.admin_containment_rules[0].denied_permissions, "iam.googleapis.com/principalaccessboundarypolicies.unbind")
    error_message = "the boundary permissions are denied only with enable_principal_access_boundary."
  }
}

# matchTagId takes the namespaced IDs (tagKeys/N, tagValues/N). The tags module
# exposes the bare numeric name, so the stage prefixes it.
run "tag_condition_uses_namespaced_ids" {
  command = plan

  variables {
    containment_tag_key_id   = "111"
    containment_tag_value_id = "222"
  }

  assert {
    condition     = output.deny_policies[0].rules[1].denial_condition.expression == "resource.matchTagId('tagKeys/111', 'tagValues/222')"
    error_message = "the audit-store rule must match the containment tag by its namespaced IDs."
  }
}

run "boundary_permissions_with_principal_access_boundary" {
  command = plan

  variables {
    enable_principal_access_boundary = true
  }

  assert {
    condition = alltrue([
      for p in ["update", "delete", "unbind"] :
      contains(output.admin_containment_rules[0].denied_permissions, "iam.googleapis.com/principalaccessboundarypolicies.${p}")
    ])
    error_message = "with a principal access boundary, its update/delete/unbind must be denied to all but break-glass."
  }
}

# The break-glass path applies the same policy by hand: the spec output is a
# gcloud deny-policy document.
run "spec_is_gcloud_policy_document" {
  command = plan

  variables {
    enable_admin_containment      = false
    containment_exempt_principals = []
    iam_deny_policies = [
      {
        name = "deny-sa-keys"
        rules = [
          {
            denied_principals  = ["principalSet://goog/public:all"]
            denied_permissions = ["iam.googleapis.com/serviceAccountKeys.create"]
            denial_condition   = { title = "t", expression = "resource.matchTag('123/env', 'prod')" }
          },
        ]
      },
    ]
  }

  assert {
    condition     = jsondecode(output.deny_policy_specs["deny-sa-keys"]).displayName == "deny-sa-keys" && jsondecode(output.deny_policy_specs["deny-sa-keys"]).rules[0].denyRule.deniedPermissions[0] == "iam.googleapis.com/serviceAccountKeys.create" && jsondecode(output.deny_policy_specs["deny-sa-keys"]).rules[0].denyRule.denialCondition.title == "t"
    error_message = "deny_policy_specs must render the gcloud deny-policy JSON (displayName, rules[].denyRule.deniedPermissions, denialCondition)."
  }

  assert {
    condition     = jsonencode(output.deny_policy_names) == jsonencode(["deny-sa-keys"])
    error_message = "user iam_deny_policies must be created alongside containment."
  }
}

# Render-only: the organization stage (legacy organization mode) applies the
# policies through its own module.iam_deny, so nothing is created here.
run "render_only_creates_nothing" {
  command = plan

  variables {
    create_deny_policies = false
  }

  assert {
    condition     = length(output.deny_policy_names) == 0 && length(output.deny_policies) == 1 && output.deny_policies[0].name == "contain-admin-identity"
    error_message = "create_deny_policies = false must render the policies without creating them."
  }
}
