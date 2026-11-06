# Principal Access Boundary (PAB) — a principal-centric boundary: the principals
# in a bound principal set can use their permissions ONLY on the resources the
# policy lists, whatever allow policies grant them. For the landing zone's
# automation service accounts this means a stolen token cannot be used against
# resources outside this organization (e.g. to exfiltrate into an attacker-owned
# project or bucket), complementing VPC-SC (data perimeter) and IAM deny
# (permission-centric). Enforcement versions pin which permissions the policy
# covers, so a Google-side expansion cannot change behaviour without an explicit
# version bump.

locals {
  boundary_resources = length(var.allowed_resources) > 0 ? var.allowed_resources : [
    "//cloudresourcemanager.googleapis.com/organizations/${var.organization_id}",
  ]
}

resource "google_iam_principal_access_boundary_policy" "this" {
  organization                        = var.organization_id
  location                            = "global"
  principal_access_boundary_policy_id = var.policy_id
  display_name                        = var.display_name

  details {
    enforcement_version = var.enforcement_version

    rules {
      description = "Principals bound to this policy may only use their permissions on these resources."
      effect      = "ALLOW"
      resources   = local.boundary_resources
    }
  }
}

# One binding per project: the principal set //cloudresourcemanager.googleapis.com/projects/<id>
# covers every service account (and service agent) that lives in that project.
resource "google_iam_projects_policy_binding" "this" {
  for_each = var.project_bindings

  project           = each.value
  location          = "global"
  policy_binding_id = "${var.policy_id}-${each.key}"
  display_name      = "PAB ${var.policy_id} on ${each.key}"
  policy_kind       = "PRINCIPAL_ACCESS_BOUNDARY"
  policy            = google_iam_principal_access_boundary_policy.this.name

  target {
    principal_set = "//cloudresourcemanager.googleapis.com/projects/${each.value}"
  }
}
