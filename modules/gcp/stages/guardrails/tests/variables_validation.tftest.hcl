# Variable validation tests for the stages/guardrails module.
# mock_provider only — no GCP credentials needed.

mock_provider "google" {}

variables {
  org_id                        = "123456789"
  enable_admin_containment      = true
  containment_exempt_principals = ["principalSet://goog/group/break-glass@acme.io"]
  containment_tag_key_id        = "tagKeys/111"
  containment_tag_value_id      = "tagValues/222"
}

run "rejects_empty_org_id" {
  command = plan

  variables {
    org_id = ""
  }

  expect_failures = [var.org_id]
}

# Without a break-glass principal the deny would lock out everyone.
run "containment_requires_exempt_principal" {
  command = plan

  variables {
    containment_exempt_principals = []
  }

  expect_failures = [var.containment_exempt_principals]
}

run "rejects_non_principal_identifier" {
  command = plan

  variables {
    containment_exempt_principals = ["group:break-glass@acme.io"]
  }

  expect_failures = [var.containment_exempt_principals]
}

run "rejects_placeholder_principal" {
  command = plan

  variables {
    containment_exempt_principals = ["principalSet://goog/group/break-glass@REPLACE-ME.invalid"]
  }

  expect_failures = [var.containment_exempt_principals]
}

# The audit-store rule is scoped by the containment tag; without its IDs the
# condition would match nothing.
run "containment_requires_tag_ids" {
  command = plan

  variables {
    containment_tag_value_id = null
  }

  expect_failures = [var.containment_tag_value_id]
}

run "rejects_duplicate_policy_names" {
  command = plan

  variables {
    iam_deny_policies = [
      {
        name  = "contain-admin-identity"
        rules = [{ denied_principals = ["principalSet://goog/public:all"], denied_permissions = ["iam.googleapis.com/serviceAccountKeys.create"] }]
      },
    ]
  }

  expect_failures = [var.iam_deny_policies]
}
