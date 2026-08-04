# Data sources for organization and billing

# Fetch organization details via domain
data "google_organization" "org" {
  domain = var.domain
}

# Fetch billing account details
# Allows looking up by ID (if provided) or display name
data "google_billing_account" "billing" {
  billing_account = var.billing_account
  display_name    = var.billing_account == null ? var.billing_account_display_name : null
  open            = true

  lifecycle {
    precondition {
      condition     = var.billing_account != null || var.billing_account_display_name != null
      error_message = "Either billing_account (ID) or billing_account_display_name must be set."
    }
  }
}
