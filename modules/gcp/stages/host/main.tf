/**
 * Copyright 2023 Ashes
 *
 * Host Module - DEPRECATED unified network stack
 *
 * Deprecated: kept unchanged for one deprecation cycle so external callers'
 * state is untouched. In-repo callers now use the purpose-built compositions
 * stages/net-hub, stages/net-spoke and stages/dns-anchor (over the shared
 * network/tiered-vpc core); see README.md for the migration guide.
 */

# =============================================================================
# CORE NETWORKING
# =============================================================================

locals {
  # Network tags for tiered security
  network_tags = {
    api_gateway = "api-gateway"
    public      = "public"
    compute     = "compute"
    database    = "database"
  }

  # Calculate subnets dynamically
  public_cidrs   = length(var.subnet_cidrs.public) > 0 ? var.subnet_cidrs.public : [for i, z in local.zones : cidrsubnet(var.vpc_cidr_block, 8, i)]
  private_cidrs  = length(var.subnet_cidrs.private) > 0 ? var.subnet_cidrs.private : [for i, z in local.zones : cidrsubnet(var.vpc_cidr_block, 8, 16 + i)]
  database_cidrs = length(var.subnet_cidrs.database) > 0 ? var.subnet_cidrs.database : [for i, z in local.zones : cidrsubnet(var.vpc_cidr_block, 8, 32 + i)]

  # Use explicit zones when provided; fall back to GCP-discovered zones.
  # Production deployments should set var.explicit_zones to prevent subnet
  # recreation if the API returns a different zone count between plans.
  zones = length(var.explicit_zones) > 0 ? var.explicit_zones : data.google_compute_zones.available.names
}

# Auto-discover available zones (used only when var.explicit_zones is empty)
data "google_compute_zones" "available" {
  project = var.project_id
  region  = var.region

  lifecycle {
    postcondition {
      condition     = length(self.names) > 0
      error_message = "No compute zones returned for region '${var.region}' in project '${var.project_id}'. Verify the region is valid and the Compute Engine API is enabled."
    }
  }
}

# Deletion protection guard for the VPC and subnet stack.
#
# Terraform's prevent_destroy meta-argument must be a static literal — it
# cannot be set via a variable. This guard resource exists ONLY when
# enable_deletion_protection = true and carries a static prevent_destroy = true.
# Any plan that would remove it (e.g. setting enable_deletion_protection = false)
# is blocked by Terraform. To intentionally deprovision a protected stack, first
# run: terraform state rm module.<name>.terraform_data.deletion_protection_guard
resource "terraform_data" "deletion_protection_guard" {
  count = var.enable_networking && var.enable_deletion_protection ? 1 : 0

  input = "${var.project_id}/${var.vpc_name}"

  lifecycle {
    prevent_destroy = true
  }
}

# Guard: each explicitly-provided CIDR list must cover at least as many entries as
# there are availability zones. When a list is shorter than the zone count, the
# subnet for_each will attempt to read an out-of-bounds index (local.*_cidrs[each.value])
# and produce a cryptic "Invalid index" error at plan time.
# This precondition surfaces the root cause immediately with an actionable message.
resource "terraform_data" "subnet_cidr_count_guard" {
  count = var.enable_networking ? 1 : 0

  lifecycle {
    precondition {
      condition = (
        length(var.subnet_cidrs.public) == 0 || length(var.subnet_cidrs.public) >= length(local.zones)
        ) && (
        length(var.subnet_cidrs.private) == 0 || length(var.subnet_cidrs.private) >= length(local.zones)
        ) && (
        length(var.subnet_cidrs.database) == 0 || length(var.subnet_cidrs.database) >= length(local.zones)
      )
      error_message = "Each non-empty subnet_cidrs list must have at least as many entries as availability zones in the region. Detected ${length(local.zones)} zones; provided public=${length(var.subnet_cidrs.public)}, private=${length(var.subnet_cidrs.private)}, database=${length(var.subnet_cidrs.database)} CIDRs. Either add CIDRs or leave the list empty to use auto-generated values."
    }
  }
}
