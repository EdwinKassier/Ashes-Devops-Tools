# gcp-guardrails root: the org-node IAM deny policies (admin containment +
# iam_deny_policies), authored from config/landing-zone.yaml and applied by the
# security team.
#
# Separation of duties: this workspace runs as the gcp-bootstrap
# <prefix>-guardrails-plan / -apply SAs, WIF-bound to it by immutable workspace
# ID. The apply SA is the only automation identity with roles/iam.denyAdmin, so
# the gcp-organization identity, which the containment policy constrains,
# cannot remove it. tfc-admin places this workspace in its own HCP project
# where only the security team can queue and confirm runs, with no speculative
# plans and no auto-apply. Needs guardrail_owner_mode = "separate" in
# gcp-bootstrap and gcp-organization (in the legacy organization mode the
# organization root applies the same policies and this root must not run).
module "guardrails" {
  source = "../../../modules/gcp/stages/guardrails"

  org_id = data.google_organization.org.org_id

  enable_admin_containment         = local.containment_on
  containment_exempt_principals    = local.containment_exempt_principals
  containment_tag_key_id           = try(data.google_tags_tag_key.containment[0].name, null)
  containment_tag_value_id         = try(data.google_tags_tag_value.containment_protected[0].name, null)
  enable_principal_access_boundary = local.enable_principal_access_boundary
  iam_deny_policies                = var.iam_deny_policies
}
