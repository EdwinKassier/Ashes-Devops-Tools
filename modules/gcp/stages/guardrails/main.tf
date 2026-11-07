# Guardrails stage: the org-node IAM deny policies (admin containment plus the
# caller's iam_deny_policies).
#
# Separation of duties. The gcp-organization apply identity is the identity the
# containment policy constrains, and iam.denypolicies.* is not deny-supported,
# so a deny policy cannot protect itself. In the default guardrail_owner_mode =
# "separate" these policies are applied by the gcp-guardrails workspace as the
# <prefix>-guardrails-apply SA (gcp-bootstrap), the only automation identity
# that holds roles/iam.denyAdmin. That workspace lives in its own HCP project
# where only the security team can queue and confirm applies (tfc-admin).
#
# The legacy organization mode calls this stage with create_deny_policies =
# false: it only renders the policies, and the organization stage applies them
# through its own module.iam_deny (so existing state addresses do not move).

locals {
  # matchTagId takes the namespaced IDs. The tags module and the tag data
  # sources expose the bare numeric name, so prefix it when it is missing.
  containment_tag_key_id = var.containment_tag_key_id == null ? "" : (
    startswith(var.containment_tag_key_id, "tagKeys/") ? var.containment_tag_key_id : "tagKeys/${var.containment_tag_key_id}"
  )
  containment_tag_value_id = var.containment_tag_value_id == null ? "" : (
    startswith(var.containment_tag_value_id, "tagValues/") ? var.containment_tag_value_id : "tagValues/${var.containment_tag_value_id}"
  )

  # Containment of the automation (Terraform-admin) identity. A CI/WIF
  # compromise of that SA could otherwise erase or blind the audit trail and
  # remove the VPC-SC data perimeter. Two deny rules, both exempting only
  # containment_exempt_principals (break-glass):
  #
  #  1. ORG-WIDE (unconditional): mutation of logging sinks/exclusions/log
  #     buckets and of VPC-SC perimeters/access policies. NOTE: this includes
  #     sinks.update and servicePerimeters.update, which Terraform uses
  #     legitimately. Once enabled, ANY change to a sink, exclusion or perimeter
  #     anywhere in the org (including workload perimeters/flow-log sinks) must be
  #     applied by a break-glass/exempt principal. That is the point: the
  #     automation identity can no longer retarget or blank the audit sink or
  #     empty a perimeter. Sink/perimeter CREATION stays allowed.
  #  2. TAG-SCOPED to the audit store (tag containment/protected, bound by the
  #     organization stage to the audit + access-log buckets, the audit Log
  #     Analytics bucket and the audit CMEK keyring): bucket delete/IAM change,
  #     bucket tag-binding delete (so the tag that scopes this rule cannot be
  #     stripped first), object delete, key-version destroy and disable
  #     (cryptoKeyVersions.update), key IAM change. IAM deny conditions can ONLY
  #     match resource tags, so the tag is how the deny is scoped to the audit
  #     bucket rather than every bucket.
  #
  # Every permission below was checked against the IAM deny supported-permissions
  # list (docs.cloud.google.com/iam/docs/deny-permissions-support, re-verified
  # 2026-11). Permissions requested but OMITTED because they are not on it:
  #  - iam.denypolicies.update / iam.denypolicies.delete: a deny policy cannot
  #    protect itself; the control-plane watch "deny_policy_change" alerts instead.
  #  - accesscontextmanager.accessPolicies.delete: the supported name is
  #    accesscontextmanager.googleapis.com/policies.delete (used below).
  #  - resourcemanager.tagValueBindings.delete / tagValues.delete / tagKeys.delete
  #    and cloudkms keyRings.deleteTagBinding: not deny-supported. The bucket
  #    tag binding IS protected (storage buckets.deleteTagBinding); the keyring
  #    binding and the tag key/value are covered by the control-plane watch
  #    "tag_binding_change" (a tag value with live bindings cannot be deleted).
  # orgpolicy.policy.set is deliberately NOT denied: Terraform sets org policies
  # every time the baseline changes; the org_policy_change watch covers it.
  containment_deny_policy = var.enable_admin_containment ? [
    {
      name         = "contain-admin-identity"
      display_name = "Contain automation identity"
      rules = [
        {
          description       = "Org-wide: deny mutation of logging sinks/exclusions/log buckets and VPC-SC perimeters to all but break-glass."
          denied_principals = ["principalSet://goog/public:all"]
          denied_permissions = concat([
            "logging.googleapis.com/sinks.update",
            "logging.googleapis.com/sinks.delete",
            "logging.googleapis.com/exclusions.create",
            "logging.googleapis.com/exclusions.update",
            "logging.googleapis.com/exclusions.delete",
            "logging.googleapis.com/buckets.delete",
            "accesscontextmanager.googleapis.com/servicePerimeters.update",
            "accesscontextmanager.googleapis.com/servicePerimeters.delete",
            "accesscontextmanager.googleapis.com/servicePerimeters.replaceAll",
            "accesscontextmanager.googleapis.com/servicePerimeters.commit",
            "accesscontextmanager.googleapis.com/policies.delete",
            # Access levels gate perimeter ingress, and access-policy IAM /
            # scopes decide who may edit perimeters. Creation stays allowed (a
            # new level is inert until a perimeter, itself protected, uses it).
            "accesscontextmanager.googleapis.com/accessLevels.update",
            "accesscontextmanager.googleapis.com/accessLevels.delete",
            "accesscontextmanager.googleapis.com/accessLevels.replaceAll",
            "accesscontextmanager.googleapis.com/authorizedOrgsDescs.create",
            "accesscontextmanager.googleapis.com/authorizedOrgsDescs.update",
            "accesscontextmanager.googleapis.com/authorizedOrgsDescs.delete",
            "accesscontextmanager.googleapis.com/policies.update",
            "accesscontextmanager.googleapis.com/policies.setIamPolicy",
            ], var.enable_principal_access_boundary ? [
            # The automation boundary must not be loosened or unbound by the
            # identities it bounds (bind/create stay allowed).
            "iam.googleapis.com/principalaccessboundarypolicies.update",
            "iam.googleapis.com/principalaccessboundarypolicies.delete",
            "iam.googleapis.com/principalaccessboundarypolicies.unbind",
          ] : [])
          exception_principals = var.containment_exempt_principals
          denial_condition     = null
        },
        {
          description       = "Audit store (tag containment/protected): deny bucket delete/update/IAM change/untag, object delete, key-version destroy/disable, key and keyring IAM change and Log Analytics bucket update/untag to all but break-glass."
          denied_principals = ["principalSet://goog/public:all"]
          denied_permissions = [
            "storage.googleapis.com/buckets.delete",
            "storage.googleapis.com/buckets.setIamPolicy",
            "storage.googleapis.com/buckets.deleteTagBinding",
            # Buckets.update covers retention policy, lifecycle, versioning,
            # soft delete, CMEK and logging config of the audit buckets.
            "storage.googleapis.com/buckets.update",
            "storage.googleapis.com/objects.delete",
            "cloudkms.googleapis.com/cryptoKeyVersions.destroy",
            "cloudkms.googleapis.com/cryptoKeyVersions.update",
            "cloudkms.googleapis.com/cryptoKeys.setIamPolicy",
            "cloudkms.googleapis.com/keyRings.setIamPolicy",
            # The audit Log Analytics bucket: retention / lock / analytics
            # changes and untagging.
            "logging.googleapis.com/buckets.update",
            "logging.googleapis.com/buckets.deleteTagBinding",
          ]
          exception_principals = var.containment_exempt_principals
          denial_condition = {
            title       = "audit-store-only"
            description = "Applies only to resources carrying the containment/protected tag (the audit buckets, the audit Log Analytics bucket and the audit CMEK keyring)."
            expression  = "resource.matchTagId('${local.containment_tag_key_id}', '${local.containment_tag_value_id}')"
          }
        },
      ]
    }
  ] : []

  deny_policies = concat(local.containment_deny_policy, var.iam_deny_policies)

  # gcloud-ready policy files for the break-glass path (PAM-elevated
  # guardrail_owner_members impersonating the guardrails SA):
  #   gcloud iam policies create|update <id> \
  #     --attachment-point=cloudresourcemanager.googleapis.com/organizations/<org> \
  #     --kind=denypolicies --policy-file=<file>
  deny_policy_specs = {
    for p in local.deny_policies : p.name => jsonencode({
      displayName = try(coalesce(p.display_name), p.name)
      rules = [
        for r in p.rules : {
          description = try(coalesce(r.description), "")
          denyRule = merge(
            {
              deniedPrincipals     = r.denied_principals
              deniedPermissions    = r.denied_permissions
              exceptionPrincipals  = try(r.exception_principals, null) == null ? [] : r.exception_principals
              exceptionPermissions = try(r.exception_permissions, null) == null ? [] : r.exception_permissions
            },
            r.denial_condition == null ? {} : {
              denialCondition = {
                title       = try(r.denial_condition.title, null)
                description = try(r.denial_condition.description, null)
                expression  = r.denial_condition.expression
              }
            },
          )
        }
      ]
    })
  }

  parent = urlencode("cloudresourcemanager.googleapis.com/organizations/${var.org_id}")
}

module "iam_deny" {
  source = "../../iam/deny-policy"

  parent = local.parent
  # A filtering for (not a conditional): a tuple of rules and [] do not unify
  # in every evaluator (tflint rejects it); the planned list is the same.
  deny_policies = [for p in local.deny_policies : p if var.create_deny_policies]
}
