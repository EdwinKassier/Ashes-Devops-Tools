# Production hardening overlay for envs/gcp/organization. Apply IN ADDITION to your own tfvars.
#
# Enforce CMEK on sensitive services org-wide (gcp.restrictNonCmekServices).
# PREREQUISITE: CMEK keys must already be wired for every service in
# cmek_required_services, or new resources of those types will fail to create.
enable_cmek_org_policy = true

# IAM deny-policy backstop on audit sinks/buckets and VPC-SC perimeters. VALIDATE ON A
# NON-PROD ORG FIRST and set your break-glass group, or the validation blocks the apply.
# NOTE: today this denies deletes only (see docs/audit/2026-11-05-enterprise-boilerplate-audit.md C3).
# enable_admin_containment      = true
# containment_exempt_principals = ["principalSet://goog/group/break-glass@your-domain.com"]

# Audit-log WORM lock. IRREVERSIBLE: a locked retention policy can never be shortened
# or removed. Enable only once retention is final and a compliance regime requires it.
# enable_audit_bucket_lock = true
