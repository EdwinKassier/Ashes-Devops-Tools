/**
 * ## Overview
 *
 * The single GCP **project primitive** for the landing zone (Cloud Foundation
 * Fabric `project`-module style). Every stage that creates a project —
 * `stages/bootstrap` (admin project), `stages/projects` (hub / DNS / env host
 * projects) and `stages/workload` (service-team projects) — calls this module,
 * so the project baseline (no default network, `PREVENT` deletion policy, APIs
 * left enabled on destroy) is defined in exactly one place.
 *
 * The module has **no naming scheme**: `project_id` and `name` are passed in
 * verbatim. Prefixes, environment keys and random suffixes belong to the calling
 * stage.
 *
 * Optional features (all off by default): Shared VPC service-project attachment,
 * additive IAM, Essential Contacts, a deletion lien and resource-manager tag
 * bindings.
 */

locals {
  parent_is_folder = startswith(var.parent, "folders/")

  # Flatten role => members into one additive binding per (role, member).
  iam_members = merge([
    for role, members in var.iam : {
      for member in members : "${role}|${member}" => {
        role   = role
        member = member
      }
    }
  ]...)
}

# ─── Project ─────────────────────────────────────────────────────────────────

resource "google_project" "this" {
  name       = coalesce(var.name, var.project_id)
  project_id = var.project_id

  # Exactly one of folder_id / org_id is set, derived from var.parent.
  folder_id = local.parent_is_folder ? trimprefix(var.parent, "folders/") : null
  org_id    = local.parent_is_folder ? null : trimprefix(var.parent, "organizations/")

  billing_account = var.billing_account
  labels          = var.labels

  # Landing-zone baseline: never create the legacy default VPC (networking is
  # owned by the host / hub stages), and never let a routine plan delete the
  # project unless the caller opts out explicitly.
  auto_create_network = false
  deletion_policy     = var.deletion_policy
}

# ─── APIs ────────────────────────────────────────────────────────────────────

resource "google_project_service" "this" {
  for_each = toset(var.services)

  project = google_project.this.project_id
  service = each.key

  # Disabling an API on destroy can break resources other stacks still own;
  # leave services enabled (the project's own deletion removes them).
  disable_dependent_services = false
  disable_on_destroy         = false
}

# ─── Shared VPC service-project attachment ───────────────────────────────────

resource "google_compute_shared_vpc_service_project" "this" {
  count = var.shared_vpc_host_project_id != null ? 1 : 0

  host_project    = var.shared_vpc_host_project_id
  service_project = google_project.this.project_id

  # The attachment needs compute.googleapis.com live on the service project.
  depends_on = [google_project_service.this]
}

# ─── IAM (additive) ──────────────────────────────────────────────────────────

# google_project_iam_member is additive: bindings granted outside this module
# (other stages, break-glass) are never evicted.
resource "google_project_iam_member" "this" {
  for_each = local.iam_members

  project = google_project.this.project_id
  role    = each.value.role
  member  = each.value.member
}

# ─── Essential Contacts ──────────────────────────────────────────────────────

resource "google_essential_contacts_contact" "this" {
  for_each = var.essential_contacts

  parent                              = "projects/${google_project.this.project_id}"
  email                               = each.key
  language_tag                        = var.essential_contacts_language
  notification_category_subscriptions = each.value

  depends_on = [google_project_service.this]
}

# ─── Lien ────────────────────────────────────────────────────────────────────

resource "google_resource_manager_lien" "this" {
  count = var.lien_reason != null ? 1 : 0

  parent       = "projects/${google_project.this.number}"
  restrictions = ["resourcemanager.projects.delete"]
  origin       = "terraform-project-module"
  reason       = var.lien_reason
}

# ─── Tag bindings ────────────────────────────────────────────────────────────

resource "google_tags_tag_binding" "this" {
  for_each = var.tag_bindings

  parent    = "//cloudresourcemanager.googleapis.com/projects/${google_project.this.number}"
  tag_value = each.value
}
