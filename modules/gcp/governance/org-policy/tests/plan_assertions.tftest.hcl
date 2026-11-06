# Plan assertions for the governance/org-policy module: verify boolean/list policies
# are planned under the caller-supplied parent with the expected constraint names.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  parent = "organizations/123456789"
  boolean_policies = [
    {
      constraint = "compute.requireShieldedVm"
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
    condition     = google_org_policy_policy.boolean_policies["compute.requireShieldedVm"].parent == var.parent
    error_message = "Boolean policy parent must be the caller-supplied parent."
  }

  assert {
    condition     = google_org_policy_policy.boolean_policies["compute.requireShieldedVm"].name == "${var.parent}/policies/compute.requireShieldedVm"
    error_message = "Boolean policy name must be <parent>/policies/<constraint>."
  }
}

# Managed constraints: with prefer_managed_constraints (default) a legacy
# constraint with a like-for-like managed equivalent is set through the managed
# version; constraints without one stay legacy.
run "legacy_constraints_translated_to_managed" {
  command = plan

  variables {
    boolean_policies = [
      { constraint = "iam.disableServiceAccountKeyCreation", enforce = true },
      { constraint = "iam.automaticIamGrantsForDefaultServiceAccounts", enforce = true },
      { constraint = "compute.requireShieldedVm", enforce = true },
    ]
    list_policies = [
      { constraint = "compute.vmExternalIpAccess", deny_all = true },
      { constraint = "gcp.resourceLocations", allowed_values = ["in:eu-locations"] },
    ]
  }

  assert {
    condition     = google_org_policy_policy.managed_policies["iam.managed.disableServiceAccountKeyCreation"].name == "${var.parent}/policies/iam.managed.disableServiceAccountKeyCreation"
    error_message = "iam.disableServiceAccountKeyCreation must be set through iam.managed.disableServiceAccountKeyCreation."
  }

  assert {
    condition     = contains(keys(google_org_policy_policy.managed_policies), "iam.managed.preventPrivilegedBasicRolesForDefaultServiceAccounts") && contains(keys(google_org_policy_policy.managed_policies), "compute.managed.vmExternalIpAccess")
    error_message = "Default-SA grants and the external-IP deny must use their managed successors."
  }

  assert {
    condition     = google_org_policy_policy.managed_policies["compute.managed.vmExternalIpAccess"].spec[0].rules[0].enforce == "TRUE"
    error_message = "A deny_all vmExternalIpAccess must become an enforced managed constraint."
  }

  assert {
    condition     = keys(google_org_policy_policy.boolean_policies) == ["compute.requireShieldedVm"] && keys(google_org_policy_policy.list_policies) == ["gcp.resourceLocations"]
    error_message = "Constraints without a managed equivalent must stay legacy, and translated ones must not also be set legacy."
  }
}

run "legacy_constraints_kept_when_managed_not_preferred" {
  command = plan

  variables {
    prefer_managed_constraints = false
    boolean_policies           = [{ constraint = "iam.disableServiceAccountKeyCreation", enforce = true }]
  }

  assert {
    condition     = length(google_org_policy_policy.managed_policies) == 0 && contains(keys(google_org_policy_policy.boolean_policies), "iam.disableServiceAccountKeyCreation")
    error_message = "prefer_managed_constraints = false must keep the legacy constraint."
  }
}

run "explicit_managed_policy_with_parameters" {
  command = plan

  variables {
    managed_policies = [
      {
        constraint = "iam.managed.allowedPolicyMembers"
        parameters = "{\"allowedPrincipalSets\":[\"//cloudresourcemanager.googleapis.com/organizations/123456789\"]}"
      },
    ]
  }

  assert {
    condition     = jsondecode(google_org_policy_policy.managed_policies["iam.managed.allowedPolicyMembers"].spec[0].rules[0].parameters).allowedPrincipalSets[0] == "//cloudresourcemanager.googleapis.com/organizations/123456789"
    error_message = "managed_policies parameters must be passed through to the policy rule."
  }
}
