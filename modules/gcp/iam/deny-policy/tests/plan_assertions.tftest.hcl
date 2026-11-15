# Plan assertions for the iam/deny-policy module (mock_provider — no creds).

mock_provider "google" {}

variables {
  parent = "cloudresourcemanager.googleapis.com%2Forganizations%2F123456789"
}

# Empty list creates nothing — the module is inert by default.
run "empty_creates_nothing" {
  command = plan

  variables {
    deny_policies = []
  }

  assert {
    condition     = length(google_iam_deny_policy.this) == 0
    error_message = "Expected no deny policies when deny_policies is empty"
  }
}

# A populated policy is materialized into a google_iam_deny_policy with the
# denied permission and exception principal wired through.
run "creates_deny_policy" {
  command = plan

  variables {
    deny_policies = [
      {
        name         = "deny-sa-key-creation"
        display_name = "Deny SA key creation"
        rules = [
          {
            description          = "Only break-glass may create SA keys"
            denied_principals    = ["principalSet://goog/public:all"]
            denied_permissions   = ["iam.googleapis.com/serviceAccountKeys.create"]
            exception_principals = ["principalSet://goog/group/break-glass@example.com"]
          }
        ]
      }
    ]
  }

  assert {
    condition     = length(google_iam_deny_policy.this) == 1
    error_message = "Expected exactly one deny policy to be planned"
  }

  assert {
    condition     = google_iam_deny_policy.this["deny-sa-key-creation"].name == "deny-sa-key-creation"
    error_message = "Deny policy name must be wired from the input"
  }

  assert {
    condition     = google_iam_deny_policy.this["deny-sa-key-creation"].parent == "cloudresourcemanager.googleapis.com%2Forganizations%2F123456789"
    error_message = "Deny policy must attach to the provided parent"
  }

  # Re-audit 5 IAC-1: assert what the planned policy denies, not just that it
  # exists. A swapped or dropped principal list would make it deny nobody.
  assert {
    condition = (
      toset(google_iam_deny_policy.this["deny-sa-key-creation"].rules[0].deny_rule[0].denied_principals) == toset(["principalSet://goog/public:all"]) &&
      toset(google_iam_deny_policy.this["deny-sa-key-creation"].rules[0].deny_rule[0].denied_permissions) == toset(["iam.googleapis.com/serviceAccountKeys.create"]) &&
      toset(google_iam_deny_policy.this["deny-sa-key-creation"].rules[0].deny_rule[0].exception_principals) == toset(["principalSet://goog/group/break-glass@example.com"]) &&
      length(google_iam_deny_policy.this["deny-sa-key-creation"].rules[0].deny_rule[0].denial_condition) == 0
    )
    error_message = "The planned deny rule must carry exactly the input's denied principals, denied permissions and exception principals, with no condition."
  }

  assert {
    condition     = output.deny_policy_rules["deny-sa-key-creation"][0].exception_principals == google_iam_deny_policy.this["deny-sa-key-creation"].rules[0].deny_rule[0].exception_principals && output.deny_policy_rules["deny-sa-key-creation"][0].condition_expression == null
    error_message = "deny_policy_rules must report the planned rule."
  }
}

# Re-audit 5 IAC-1: a denial condition is planned exactly as given.
run "conditional_rule_keeps_its_condition" {
  command = plan

  variables {
    deny_policies = [
      {
        name = "deny-audit-store"
        rules = [
          {
            denied_principals    = ["principalSet://goog/public:all"]
            denied_permissions   = ["storage.googleapis.com/buckets.delete"]
            exception_principals = ["principalSet://goog/group/break-glass@example.com"]
            denial_condition = {
              title      = "audit-store-only"
              expression = "resource.matchTagId('tagKeys/1', 'tagValues/2')"
            }
          }
        ]
      }
    ]
  }

  assert {
    condition     = google_iam_deny_policy.this["deny-audit-store"].rules[0].deny_rule[0].denial_condition[0].expression == "resource.matchTagId('tagKeys/1', 'tagValues/2')"
    error_message = "The denial condition expression must be planned as given."
  }

  assert {
    condition     = output.deny_policy_rules["deny-audit-store"][0].condition_expression == "resource.matchTagId('tagKeys/1', 'tagValues/2')"
    error_message = "deny_policy_rules must report the planned condition."
  }
}
