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
}
