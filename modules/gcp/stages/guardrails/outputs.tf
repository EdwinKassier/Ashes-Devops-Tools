output "parent" {
  description = "URL-encoded org attachment point of the deny policies."
  value       = local.parent
}

output "deny_policies" {
  description = "Rendered deny policies (admin containment + iam_deny_policies), in the deny-policy module's input shape. The organization stage applies these itself in its legacy organization mode."
  value       = local.deny_policies
}

output "deny_policy_names" {
  description = "Names of the deny policies this stage creates at the org node (empty when create_deny_policies = false)."
  value       = module.iam_deny.deny_policy_names
}

output "deny_policy_ids" {
  description = "Map of deny-policy name to resource ID (empty when create_deny_policies = false)."
  value       = module.iam_deny.deny_policy_ids
}

output "deny_policy_specs" {
  description = "Map of deny-policy ID => gcloud policy-file JSON, for the break-glass path only: gcloud iam policies create|update <id> --attachment-point=cloudresourcemanager.googleapis.com/organizations/<org> --kind=denypolicies --policy-file=<file>."
  value       = local.deny_policy_specs
}

output "admin_containment_rules" {
  description = "Rules of the admin-containment deny policy (empty when enable_admin_containment = false): denied permissions, exempt principals and whether the rule is tag-scoped to the audit store."
  value = flatten([
    for p in local.containment_deny_policy : [
      for r in p.rules : {
        description          = r.description
        denied_permissions   = r.denied_permissions
        exception_principals = r.exception_principals
        tag_scoped           = r.denial_condition != null
      }
    ]
  ])
}
