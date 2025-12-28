# Resource Manager Tags Module
# Manages Organization-level Tag Keys and Values

resource "google_tags_tag_key" "keys" {
  for_each = var.tags

  parent      = "organizations/${var.org_id}"
  short_name  = each.key
  description = "Managed by Terraform"
}

resource "google_tags_tag_value" "values" {
  for_each = {
    for pair in flatten([
      for key, values in var.tags : [
        for value in values : {
          key   = key
          value = value
        }
      ]
    ]) : "${pair.key}-${pair.value}" => pair
  }

  parent      = google_tags_tag_key.keys[each.value.key].name
  short_name  = each.value.value
  description = "Managed by Terraform"
}
