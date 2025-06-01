terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
  }
}

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
output "memberships" {
  description = "Map of created group memberships"
  value = {
    for k, v in google_cloud_identity_group_membership.membership : k => {
      name   = v.name
      id     = v.id
      member = v.preferred_member_key[0].id
      roles  = v.roles[*].name
    }
  }
}
