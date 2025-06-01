terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
  }
}

# Data source for the organization
data "google_organization" "org" {
  domain = var.domain
}

# Create folders (equivalent to organizational units in GCP)
resource "google_folder" "business_units" {
  for_each = var.business_units

  display_name = each.key
  parent       = "organizations/${data.google_organization.org.org_id}"
}

# Create sub-folders for environments under each business unit
resource "google_folder" "environments" {
  for_each = {
    for pair in local.environment_pairs : "${pair.bu}.${pair.env}" => pair
  }

  display_name = each.value.env
  parent       = google_folder.business_units[each.value.bu].name
}

locals {
  environment_pairs = flatten([
    for bu in keys(var.business_units) : [
      for env in var.environments : {
        bu  = bu
        env = env
      }
    ]
  ])
} 