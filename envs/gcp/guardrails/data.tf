# This root never reads gcp-organization outputs: a reader of that state could
# be steered by whoever controls the gcp-organization workspace, the identity
# the containment policy constrains. It resolves what it needs from GCP.

data "google_organization" "org" {
  domain = local.domain
}

# The containment/protected tag that scopes the audit-store rule. gcp-organization
# creates it and binds it to the audit store (enable_admin_containment). Looking
# it up fails the plan if it does not exist yet: apply gcp-organization first.
data "google_tags_tag_key" "containment" {
  count = local.containment_on ? 1 : 0

  parent     = "organizations/${data.google_organization.org.org_id}"
  short_name = "containment"
}

data "google_tags_tag_value" "containment_protected" {
  count = local.containment_on ? 1 : 0

  parent     = data.google_tags_tag_key.containment[0].id
  short_name = "protected"
}
