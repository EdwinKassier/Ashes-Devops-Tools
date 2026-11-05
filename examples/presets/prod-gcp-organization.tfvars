# Production hardening overlay for envs/gcp/organization. Apply IN ADDITION to your own tfvars.
#
# Enforce CMEK on sensitive services org-wide (gcp.restrictNonCmekServices).
# PREREQUISITE: CMEK keys must already be wired for every service in
# cmek_required_services, or new resources of those types will fail to create.
enable_cmek_org_policy = true

# Admin containment (audit C2/C3): IAM deny policy at the org node. Org-wide it blocks
# logging sink update/delete, exclusion create/update/delete, log-bucket delete and
# VPC-SC perimeter update/delete/replaceAll/commit + access-policy delete; tag-scoped
# to the audit buckets and audit CMEK keyring it blocks bucket delete/setIamPolicy,
# object delete, key-version destroy and key setIamPolicy. Only the principals below
# are exempt — so after this is on, ANY Terraform change to a sink, exclusion or
# perimeter must be applied as break-glass (docs/runbooks/production-hardening.md).
# The placeholder below is REJECTED by variable validation on purpose: replace it with
# your real break-glass group or the plan fails. Validate on a non-prod org first.
enable_admin_containment      = true
containment_exempt_principals = ["principalSet://goog/group/break-glass@REPLACE-ME.invalid"]

# Control-plane alerting is on by default; give it somewhere to send alerts.
# alert_notification_emails    = ["secops@your-domain.com"]
# break_glass_principal_emails = ["bg-admin-1@your-domain.com"]

# Separation of duties: a dedicated logging project for the audit bucket, audit CMEK and
# alerts. It must NOT be owned by the Terraform admin SA. Decide before the first apply.
# logging_project_id     = "acme-logging-prod"
# logging_project_number = "123456789012"

# Audit-log WORM lock. IRREVERSIBLE: a locked retention policy can never be shortened
# or removed. Enable only once retention is final and a compliance regime requires it.
# enable_audit_bucket_lock = true
