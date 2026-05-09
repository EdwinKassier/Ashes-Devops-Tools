# Supabase Project Module
#
# Creates a single Supabase project. The database_password is written once at
# creation and then ignored — the Supabase Management API does not expose a
# programmatic password rotation endpoint, so any change to database_password
# after initial apply would have no effect and would silently drift in state.
#
# ⚠️  Deleting this resource permanently destroys the Supabase project and all
# its data. There is no soft-delete or recycle bin. Always set
# lifecycle.prevent_destroy = true on the resource that calls this module in
# production environments.

resource "supabase_project" "this" {
  organization_id   = var.organization_id
  name              = var.project_name
  database_password = var.database_password
  region            = var.region

  lifecycle {
    # The Management API does not support password rotation via Terraform.
    # Removing this block will cause Terraform to attempt (and fail) updates.
    ignore_changes = [database_password]
  }
}
