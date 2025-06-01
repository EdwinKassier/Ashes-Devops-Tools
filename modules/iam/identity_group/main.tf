terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
  }
}

# Google Cloud Identity Group resource
resource "google_cloud_identity_group" "cloud_identity_group" {
  for_each = { for group in var.identity_groups : group.id => group }

  display_name         = each.value.display_name
  description         = lookup(each.value, "description", null)
  initial_group_config = lookup(each.value, "initial_group_config", "WITH_INITIAL_OWNER")
  parent              = "customers/${var.customer_id}"

  group_key {
    id = each.value.email
  }

  labels = merge(
    {
      "cloudidentity.googleapis.com/groups.discussion_forum" = ""
    },
    lookup(each.value, "labels", {})
  )
}

# Output the group details
output "identity_groups" {
  description = "Map of created identity groups"
  value = {
    for k, v in google_cloud_identity_group.cloud_identity_group : k => {
      name   = v.name
      id     = v.id
      email  = v.group_key[0].id
    }
  }
}
