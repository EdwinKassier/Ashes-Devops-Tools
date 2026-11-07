output "tag_keys" {
  description = "Map of tag key short name to its namespaced ID (tagKeys/<n>), the form tag-value parents, tag bindings and IAM deny matchTagId take."
  value       = { for k, v in google_tags_tag_key.keys : k => "tagKeys/${trimprefix(v.name, "tagKeys/")}" }
}

output "tag_values" {
  description = "Map of \"<key>-<value>\" to the tag value's namespaced ID (tagValues/<n>), the form tag bindings and IAM deny matchTagId take."
  value       = { for k, v in google_tags_tag_value.values : k => "tagValues/${trimprefix(v.name, "tagValues/")}" }
}
