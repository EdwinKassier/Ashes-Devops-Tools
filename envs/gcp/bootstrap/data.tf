# Data sources for organization and billing (phase-0 lookups).

# Fetch organization details via domain.
data "google_organization" "org" {
  domain = local.domain
}

# Fetch billing account details. Looks up by ID (if provided) or display name.
data "google_billing_account" "billing" {
  billing_account = local.billing_account
  display_name    = local.billing_account == null ? var.billing_account_display_name : null
  open            = true

  lifecycle {
    precondition {
      condition     = local.billing_account != null || var.billing_account_display_name != null
      error_message = "Either billing_account (ID) or billing_account_display_name must be set."
    }
  }
}
