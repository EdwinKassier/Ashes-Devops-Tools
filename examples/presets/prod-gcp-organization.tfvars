# Production hardening overlay for envs/gcp/organization. Merge its keys into your own tfvars.
#
# Every key below sits in the root's gcp_overrides object. A tfvars file sets
# the WHOLE object, so a second -var-file replaces (does not merge with) your own
# gcp_overrides: copy these keys into your own gcp_overrides instead.
gcp_overrides = {
  # Enforce CMEK on sensitive services org-wide (gcp.restrictNonCmekServices).
  # PREREQUISITE: CMEK keys must already be wired for every service in
  # cmek_required_services, or new resources of those types will fail to create.
  enable_cmek_org_policy = true

  # Admin containment: IAM deny policy at the org node. Org-wide it blocks logging sink
  # update/delete, exclusion create/update/delete, log-bucket delete and VPC-SC
  # perimeter update/delete/replaceAll/commit + access-policy delete; tag-scoped to the
  # audit buckets and audit CMEK keyring it blocks bucket delete/setIamPolicy/untag,
  # object delete, key-version destroy/disable and key setIamPolicy. A check warns when
  # an is_production environment exists without it. Only the principals below
  # are exempt — so after this is on, ANY Terraform change to a sink, exclusion or
  # perimeter must be applied as break-glass (docs/runbooks/production-hardening.md).
  # The placeholder below is REJECTED by variable validation on purpose: replace it with
  # your real break-glass group or the plan fails. Validate on a non-prod org first.
  # In guardrail_owner_mode = "separate" (the default) this root only creates and
  # binds the containment tag; the security-team gcp-guardrails root applies the
  # policy and needs the same break-glass principal. Prefer gcp.break_glass_group
  # in config/landing-zone.yaml, which both roots read.
  enable_admin_containment      = true
  containment_exempt_principals = ["principalSet://goog/group/break-glass@REPLACE-ME.invalid"]

  # Control-plane alerting is on by default; give it somewhere to send alerts.
  # alert_notification_emails    = ["secops@your-domain.com"]
  # break_glass_principal_emails = ["bg-admin-1@your-domain.com"]

  # Audit store: the dedicated logging project (separation of duties) and the WORM lock
  # (IRREVERSIBLE) are set in config/landing-zone.yaml as gcp.logging_project_id,
  # gcp.logging_project_number and gcp.enable_audit_bucket_lock, so every reader sees them.
  # A gcp.environments entry with compliance_class: regulated fails the plan until they
  # are set (or gcp.audit_store_waived: true). The production profile warns once an
  # environment is_production. See docs/runbooks/production-hardening.md.

  # Standing org/billing admin is group-only (organization_admin_groups /
  # billing_admin_groups are required). Keep the user-principal escape hatch off.
  allow_user_principals_for_break_glass = false

  # Just-in-time org admin (Privileged Access Manager). Requires enable_pam = true in
  # prod-gcp-bootstrap.tfvars. The placeholders are REJECTED by variable validation on
  # purpose: replace them with your real requester / approver groups (disjoint, so
  # nobody approves their own request).
  enable_pam               = true
  pam_eligible_groups      = ["gcp-org-admin-requesters@REPLACE-ME.invalid"]
  pam_approver_groups      = ["gcp-org-admin-approvers@REPLACE-ME.invalid"]
  pam_max_request_duration = "3600s"

  # Per-environment folder-scoped VPC-SC access policies (default; listed for clarity).
  enable_scoped_access_policies = true
}
