# organization-apply's org iam.securityAdmin is role-conditioned by gcp-bootstrap
# (modifiedGrantsByRole.hasOnly(organization_apply_grantable_roles)), and it
# holds no folderAdmin. Folder IAM goes through its folderIamAdmin. Every other
# grant this stage makes through setIamPolicy, and that no unconditional role
# of organization-apply already covers, must be on the gcp-bootstrap
# allow-list, or the apply fails with 403. These checks fail the plan first and
# name what is missing.
#
# Grants that need the allow-list:
#   - roles/billing.admin on the org node (billing admin groups);
#   - roles/logging.bucketWriter and roles/logging.logWriter on the audit
#     project (the Log Analytics and control-plane sink writer identities).
#     The network log sink (CMP-02) adds no grant: it shares the org Logging
#     service account that already holds objectCreator on the audit bucket;
#   - with a separate logging project (gcp.logging_project_id), whose IAM
#     organization-apply does not administer through admin-project roles:
#     roles/storage.objectCreator on the audit buckets and
#     roles/cloudkms.cryptoKeyEncrypterDecrypter on the audit keys.
# Grants with an unconditional source (admin project): KMS keys
# (cloudkms.admin), buckets (storage.admin), Pub/Sub topics (pubsub.admin),
# BigQuery datasets (bigquery.admin), access policies
# (accesscontextmanager.policyAdmin). Audit configs modify no grant, so the
# condition admits them.
locals {
  organization_apply_granted_roles = sort(distinct(concat(
    length(local.billing_admin_members) > 0 ? ["roles/billing.admin"] : [],
    var.gcp.enable_log_analytics ? ["roles/logging.bucketWriter"] : [],
    var.gcp.enable_control_plane_alerting ? ["roles/logging.logWriter"] : [],
    local.separate_logging_project ? ["roles/storage.objectCreator", "roles/cloudkms.cryptoKeyEncrypterDecrypter"] : [],
  )))
  organization_apply_missing_roles = var.organization_apply_grantable_roles == null ? [] : sort(tolist(setsubtract(toset(local.organization_apply_granted_roles), toset(var.organization_apply_grantable_roles))))

  organization_admins_missing = var.bootstrap_organization_admin_members == null ? [] : sort(tolist(setsubtract(toset(local.org_admin_members), toset(var.bootstrap_organization_admin_members))))
}

resource "terraform_data" "organization_apply_grants_allowed" {
  input = local.organization_apply_granted_roles

  lifecycle {
    precondition {
      condition     = length(local.organization_apply_missing_roles) == 0
      error_message = "This stage grants roles that organization-apply's org iam.securityAdmin condition (gcp-bootstrap organization_apply_grantable_roles) does not admit: ${join(", ", local.organization_apply_missing_roles)}. The apply would fail with 403. Add them to the gcp-bootstrap input organization_apply_grantable_roles and apply gcp-bootstrap first. Roles that control IAM, identities or projects can never be added."
    }
  }
}

# The organization admins this stage expects must be granted by gcp-bootstrap.
resource "terraform_data" "organization_admins_granted_by_bootstrap" {
  input = local.org_admin_members

  lifecycle {
    precondition {
      condition     = length(local.organization_admins_missing) == 0
      error_message = "These organization admins get no roles/resourcemanager.organizationAdmin: ${join(", ", local.organization_admins_missing)}. gcp-bootstrap grants it (input organization_admin_members; envs/gcp/bootstrap derives it from gcp.organization_admin_groups unless its variable organization_admin_members is set). Add them there and apply gcp-bootstrap first."
    }
  }
}
