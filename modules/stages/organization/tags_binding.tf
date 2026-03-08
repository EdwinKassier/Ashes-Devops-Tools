resource "google_tags_tag_binding" "environment" {
  for_each = {
    for env_key, folder in module.organization.folders : env_key => {
      parent    = folder.name
      tag_value = module.tags.tag_values["environment-${env_key}"]
    }
    if contains(keys(module.tags.tag_values), "environment-${env_key}")
  }

  parent    = each.value.parent
  tag_value = each.value.tag_value
}
