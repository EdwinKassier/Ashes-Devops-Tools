# aws-shared-services stage (phase-2)
#
# Thin orchestration wrapper that composes the org's account-agnostic shared
# platform services ENTIRELY in the SHARED SERVICES account. There is a SINGLE
# default `aws` provider (no aliases): every child module runs in the same
# account and region.
#
# Composition (both capabilities are independently GATED and off by default):
#   - private_ca (private-ca)             — one ACM Private CA (ROOT or
#                                            SUBORDINATE), optionally shared
#                                            org-wide over RAM so member accounts
#                                            issue certificates from one CA
#                                            instead of a per-account CA fleet.
#   - secrets_baseline (secrets-baseline) — Secrets Manager secrets with
#                                            org-scoped (aws:PrincipalOrgID)
#                                            resource policies and optional
#                                            per-secret rotation.
#
# Both children bill from the moment they are enabled (ACM PCA has a fixed
# monthly per-CA charge; secrets bill per secret-month), so the stage keeps both
# gates false by default — enable them deliberately per environment.

# ---------------------------------------------------------------------------
# ACM Private CA hierarchy — org-shared internal certificate authority
# ---------------------------------------------------------------------------

module "private_ca" {
  source = "../../aws/private-ca"

  enable_private_ca = var.enable_private_ca
  ca_type           = var.ca_type
  common_name       = var.ca_common_name
  share_org         = var.share_ca_org
  org_arn           = var.org_arn
}

# ---------------------------------------------------------------------------
# Secrets Manager baseline — org-scoped secrets + optional rotation
# ---------------------------------------------------------------------------

module "secrets_baseline" {
  source = "../../aws/secrets-baseline"

  enable_secrets_baseline = var.enable_secrets_baseline
  secrets                 = var.secrets
  kms_key_id              = var.secrets_kms_key_id
  org_id                  = var.org_id
}
