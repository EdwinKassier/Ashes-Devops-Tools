
# Google Cloud Identity Group Membership resource
resource "google_cloud_identity_group_membership" "membership" {
  for_each = { for member in var.members : "${member.group_id}-${member.member_id}" => member }

  group = each.value.group_id

  preferred_member_key {
    id = each.value.member_id
  }

  dynamic "roles" {
    for_each = each.value.roles
    content {
      name = roles.value
    }
  }
}

# Output the membership details
