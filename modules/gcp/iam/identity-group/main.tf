
# Google Cloud Identity Group resource
resource "google_cloud_identity_group" "cloud_identity_group" {
  for_each = { for group in var.identity_groups : group.id => group }

  display_name         = each.value.display_name
  description          = each.value.description
  initial_group_config = each.value.initial_group_config
  parent               = "customers/${var.customer_id}"

  group_key {
    id = each.value.email
  }

  labels = merge(
    {
      "cloudidentity.googleapis.com/groups.discussion_forum" = ""
    },
    each.value.labels
  )
}

# Output the group details
