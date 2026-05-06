# Example: define org-level tag keys and allowed values.
# Tags can then be bound to projects/folders to drive org-policy conditions.

locals {
  org_id = "123456789012"
}

module "resource_tags" {
  source = "../../"

  org_id = local.org_id

  tags = {
    "environment" = ["dev", "staging", "prod"]
    "team"        = ["platform", "backend", "frontend", "data"]
    "cost-center" = ["engineering", "marketing", "operations"]
  }
}

output "tag_keys" {
  description = "Tag key resources keyed by short name"
  value       = module.resource_tags.tag_keys
}

output "tag_values" {
  description = "Tag value resources keyed by 'key/value'"
  value       = module.resource_tags.tag_values
}
