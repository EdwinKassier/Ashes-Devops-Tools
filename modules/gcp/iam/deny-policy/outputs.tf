output "deny_policy_ids" {
  description = "Map of deny-policy name to the created google_iam_deny_policy resource ID."
  value       = { for k, v in google_iam_deny_policy.this : k => v.id }
}

output "deny_policy_names" {
  description = "List of deny-policy names created."
  value       = keys(google_iam_deny_policy.this)
}

output "deny_policy_rules" {
  description = "Map of deny-policy name to its planned rules, read from the google_iam_deny_policy resource (not the input): denied and exception principals and permissions, and the denial condition expression (null when unconditional). Lets callers' tests assert what the policy will actually deny."
  value = {
    for k, v in google_iam_deny_policy.this : k => [
      for r in v.rules : {
        denied_principals     = try(r.deny_rule[0].denied_principals, null)
        denied_permissions    = try(r.deny_rule[0].denied_permissions, null)
        exception_principals  = try(r.deny_rule[0].exception_principals, null)
        exception_permissions = try(r.deny_rule[0].exception_permissions, null)
        condition_expression  = try(r.deny_rule[0].denial_condition[0].expression, null)
      }
    ]
  }
}
