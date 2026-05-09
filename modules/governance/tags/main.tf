# Resource Manager Tags Module
# Manages Organization-level Tag Keys and Values

resource "google_tags_tag_key" "keys" {
  for_each = var.tags

  parent      = "organizations/${var.org_id}"
  short_name  = each.key
  description = each.value.description
}

resource "google_tags_tag_value" "values" {
  for_each = {
    for pair in flatten([
      for key, cfg in var.tags : [
        for value in cfg.values : {
          key         = key
          value       = value
          description = cfg.description
        }
      ]
    ]) : "${pair.key}-${pair.value}" => pair
  }

  parent      = google_tags_tag_key.keys[each.value.key].name
  short_name  = each.value.value
  description = each.value.description
}
