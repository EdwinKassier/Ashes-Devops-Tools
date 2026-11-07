# Just-in-time organization admin (Privileged Access Manager). Opt-in.
#
# Instead of a standing roles/resourcemanager.organizationAdmin for a person,
# members of pam_eligible_groups request the role for at most
# pam_max_request_duration, with a written justification, and a member of
# pam_approver_groups must approve. The grant expires on its own; every request,
# approval and grant is in the audit log. Requires the gcp-bootstrap enable_pam
# input (privilegedaccessmanager.admin for the organization apply SA).

resource "google_privileged_access_manager_entitlement" "org_admin" {
  count = var.gcp.enable_pam ? 1 : 0

  parent               = "organizations/${var.org_id}"
  location             = "global"
  entitlement_id       = var.pam_entitlement_id
  max_request_duration = var.gcp.pam_max_request_duration

  eligible_users {
    principals = [for g in var.gcp.pam_eligible_groups : "group:${g}"]
  }

  privileged_access {
    gcp_iam_access {
      resource      = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type = "cloudresourcemanager.googleapis.com/Organization"

      dynamic "role_bindings" {
        for_each = toset(var.pam_roles)
        content {
          role = role_bindings.value
        }
      }
    }
  }

  requester_justification_config {
    unstructured {}
  }

  approval_workflow {
    manual_approvals {
      require_approver_justification = true

      steps {
        approvals_needed = 1

        approvers {
          principals = [for g in var.gcp.pam_approver_groups : "group:${g}"]
        }
      }
    }
  }

  dynamic "additional_notification_targets" {
    for_each = length(var.pam_notification_emails) > 0 ? [1] : []
    content {
      admin_email_recipients = var.pam_notification_emails
    }
  }
}
