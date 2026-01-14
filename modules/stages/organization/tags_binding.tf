
# Tag Bindings
resource "google_tags_tag_binding" "env_dev" {
  parent    = module.organization.folders["dev"].name
  tag_value = module.tags.tag_values["environment-dev"]
}

resource "google_tags_tag_binding" "env_uat" {
  parent    = module.organization.folders["uat"].name
  tag_value = module.tags.tag_values["environment-uat"]
}

resource "google_tags_tag_binding" "env_prod" {
  parent    = module.organization.folders["prod"].name
  tag_value = module.tags.tag_values["environment-prod"]
}
