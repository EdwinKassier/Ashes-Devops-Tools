# Example: define org-level tag keys and allowed values.
# Tags can then be bound to projects/folders to drive org-policy conditions.
#
# Each tag key takes an object with:
#   values      = list(string)             — allowed tag values (required)
#   description = optional(string, "...")  — shown in GCP console (optional)

locals {
  org_id = "123456789012"
}

module "resource_tags" {
  source = "../../"

  org_id = local.org_id

  tags = {
    "environment" = {
      values      = ["dev", "staging", "prod"]
      description = "Deployment environment tier"
    }
    "team" = {
      values      = ["platform", "backend", "frontend", "data"]
      description = "Owning engineering team"
    }
    "cost-center" = {
      values = ["engineering", "marketing", "operations"]
      # description omitted — defaults to "Managed by Terraform"
    }
  }
}
