# Example: the org-node IAM deny policies of the landing zone. In a full
# deployment this is invoked from envs/gcp/guardrails/main.tf (the
# security-team gcp-guardrails workspace), which resolves the org and the
# containment tag created by gcp-organization. Replace the locals with yours.

locals {
  org_id                   = "123456789012"
  containment_tag_key_id   = "tagKeys/281484271805521"
  containment_tag_value_id = "tagValues/281479612808422"
}

module "guardrails" {
  source = "../../"

  org_id = local.org_id

  enable_admin_containment      = true
  containment_exempt_principals = ["principalSet://goog/group/gcp-break-glass@acme.io"]
  containment_tag_key_id        = local.containment_tag_key_id
  containment_tag_value_id      = local.containment_tag_value_id

  iam_deny_policies = [
    {
      name         = "deny-sa-key-creation"
      display_name = "Deny service-account key creation"
      rules = [
        {
          denied_principals    = ["principalSet://goog/public:all"]
          denied_permissions   = ["iam.googleapis.com/serviceAccountKeys.create"]
          exception_principals = ["principalSet://goog/group/gcp-break-glass@acme.io"]
        },
      ]
    },
  ]
}
