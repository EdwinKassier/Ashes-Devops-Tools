# Root behaviour test for the gcp-guardrails root: the security-team workspace
# that authors the org IAM deny policies from config/landing-zone.yaml and
# applies them as the gcp-bootstrap guardrails SA. It never reads
# gcp-organization outputs: the org and the containment tag are looked up
# directly (overridden here). mock_provider only — no GCP credentials needed.

mock_provider "google" {}

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  domain                   = "acme.io"
  project_prefix           = "acme"
}

override_data {
  target = data.google_organization.org
  values = {
    org_id = "111122223333"
  }
}

override_data {
  target = data.google_tags_tag_key.containment
  values = {
    id   = "tagKeys/111"
    name = "111"
  }
}

override_data {
  target = data.google_tags_tag_value.containment_protected
  values = {
    id   = "tagValues/222"
    name = "222"
  }
}

# A production estate in config turns containment on, exempting the config
# break-glass group, scoped by the containment tag the root looked up.
run "containment_spec_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-prod.yaml"
    domain                   = null
    project_prefix           = null
  }

  assert {
    condition     = output.admin_containment_enabled == true && jsonencode(output.deny_policy_names) == jsonencode(["contain-admin-identity"])
    error_message = "a production estate must plan the contain-admin-identity deny policy."
  }

  assert {
    condition = alltrue([
      for r in module.guardrails.admin_containment_rules :
      jsonencode(r.exception_principals) == jsonencode(["principalSet://goog/group/gcp-break-glass@acme.io"])
    ])
    error_message = "every containment rule must exempt the break-glass group from gcp.break_glass_group."
  }

  assert {
    condition     = module.guardrails.deny_policies[0].rules[1].denial_condition.expression == "resource.matchTagId('tagKeys/111', 'tagValues/222')"
    error_message = "the audit-store rule must match the containment/protected tag looked up under the organization."
  }

  assert {
    condition     = module.guardrails.parent == "cloudresourcemanager.googleapis.com%2Forganizations%2F111122223333"
    error_message = "the deny policy must attach to the organization resolved from org.domain."
  }

  assert {
    condition     = data.google_tags_tag_key.containment[0].parent == "organizations/111122223333" && data.google_tags_tag_key.containment[0].short_name == "containment"
    error_message = "the containment tag key must be looked up under the organization, not read from gcp-organization."
  }

  assert {
    condition     = contains(keys(output.deny_policy_specs), "contain-admin-identity")
    error_message = "the break-glass spec must be exposed."
  }
}

run "no_production_no_containment" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-dev-only.yaml"
    domain                   = null
    project_prefix           = null
  }

  assert {
    condition     = output.admin_containment_enabled == false && length(output.deny_policy_names) == 0
    error_message = "without a production environment no containment deny policy is planned."
  }

  assert {
    condition     = length(data.google_tags_tag_key.containment) == 0 && length(data.google_tags_tag_value.containment_protected) == 0
    error_message = "the containment tag is looked up only when containment is on."
  }
}

# gcp.admin_containment: false is the explicit waiver (unset is not).
run "config_false_waives_containment" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-prod-waived.yaml"
    domain                   = null
    project_prefix           = null
  }

  assert {
    condition     = output.admin_containment_enabled == false && length(output.deny_policy_names) == 0
    error_message = "gcp.admin_containment: false must waive containment for a production estate."
  }
}

run "production_without_break_glass_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-prod-no-break-glass.yaml"
    domain                   = null
    project_prefix           = null
  }

  expect_failures = [output.admin_containment_enabled]
}

run "rejects_placeholder_break_glass" {
  command = plan

  variables {
    enable_admin_containment      = true
    containment_exempt_principals = ["principalSet://goog/group/break-glass@REPLACE-ME.invalid"]
  }

  expect_failures = [var.containment_exempt_principals]
}

# User deny policies are authored here (they moved from gcp-organization).
run "iam_deny_policies_applied_here" {
  command = plan

  variables {
    environments = {}
    iam_deny_policies = [
      {
        name = "deny-sa-keys"
        rules = [
          {
            denied_principals  = ["principalSet://goog/public:all"]
            denied_permissions = ["iam.googleapis.com/serviceAccountKeys.create"]
          },
        ]
      },
    ]
  }

  assert {
    condition     = jsonencode(output.deny_policy_names) == jsonencode(["deny-sa-keys"]) && output.admin_containment_enabled == false
    error_message = "iam_deny_policies must be applied by this root."
  }
}

run "rejects_unset_domain" {
  command = plan

  variables {
    domain = null
  }

  expect_failures = [var.domain]
}

# The boundary is bound by gcp-organization from the same config key; the
# containment policy here must deny its update/delete/unbind, or a migration
# from gcp-organization would silently drop those rules.
run "principal_access_boundary_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-prod-pab.yaml"
    domain                   = null
    project_prefix           = null
  }

  assert {
    condition = alltrue([
      for p in ["update", "delete", "unbind"] :
      contains(module.guardrails.admin_containment_rules[0].denied_permissions, "iam.googleapis.com/principalaccessboundarypolicies.${p}")
    ])
    error_message = "gcp.principal_access_boundary: true must add the boundary deny rules."
  }
}

run "principal_access_boundary_off_by_default" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-prod.yaml"
    domain                   = null
    project_prefix           = null
  }

  assert {
    condition     = !contains(module.guardrails.admin_containment_rules[0].denied_permissions, "iam.googleapis.com/principalaccessboundarypolicies.unbind")
    error_message = "without the config key (or variable) the boundary rules stay off."
  }
}

run "principal_access_boundary_variable_wins_over_config" {
  command = plan

  variables {
    landing_zone_config_path         = "tests/fixtures/landing-zone-prod-pab.yaml"
    domain                           = null
    project_prefix                   = null
    enable_principal_access_boundary = false
  }

  assert {
    condition     = !contains(module.guardrails.admin_containment_rules[0].denied_permissions, "iam.googleapis.com/principalaccessboundarypolicies.unbind")
    error_message = "an explicit enable_principal_access_boundary = false must override the config key."
  }
}
