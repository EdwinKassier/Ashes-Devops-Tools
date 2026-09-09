# Plan assertions for the governance/org-policy module: verify boolean/list policies
# are planned under the caller-supplied parent with the expected constraint names.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  parent = "organizations/123456789"
  boolean_policies = [
    {
      constraint = "sql.restrictPublicIp"
      enforce    = true
    }
  ]
}

run "boolean_policy_wired_to_parent" {
  command = plan

  assert {
    condition     = length(google_org_policy_policy.boolean_policies) == 1
    error_message = "One boolean policy must be planned per input."
  }

  assert {
    condition     = google_org_policy_policy.boolean_policies["sql.restrictPublicIp"].parent == var.parent
    error_message = "Boolean policy parent must be the caller-supplied parent."
  }

  assert {
    condition     = google_org_policy_policy.boolean_policies["sql.restrictPublicIp"].name == "${var.parent}/policies/sql.restrictPublicIp"
    error_message = "Boolean policy name must be <parent>/policies/<constraint>."
  }
}
