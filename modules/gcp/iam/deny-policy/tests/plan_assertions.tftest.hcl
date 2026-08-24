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
}
