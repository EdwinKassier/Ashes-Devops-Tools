# Availability zones (ARC-3). Precedence: var.availability_zones (names) >
# var.availability_zone_ids > aws.network.availability_zone_ids > the region's
# first three available zones, sorted by name. An AZ ID names the same physical
# zone in every account, but a zone NAME can map to a different physical zone in
# each account. The workload roots read the same aws.network key, so with IDs set
# their spokes land in the hub's physical zones. IDs are mapped to names inside
# THIS account, and the subnets keep availability_zone (the name), so an
# unchanged name never replaces a subnet.
locals {
  availability_zone_ids = (
    var.availability_zone_ids != null ? var.availability_zone_ids :
    local.cfg.availability_zone_ids != null ? local.cfg.availability_zone_ids : []
  )
  read_availability_zones = var.availability_zones == null
}

data "aws_availability_zones" "available" {
  count = local.read_availability_zones ? 1 : 0
  state = "available"

  # Only default-enabled zones: Local Zones and Wavelength Zones need an opt-in.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }

  # A postcondition (not a guard resource) so the check adds nothing to state
  # and a failure stops the plan before any zone reaches a subnet.
  lifecycle {
    postcondition {
      condition     = alltrue([for id in local.availability_zone_ids : contains(self.zone_ids, id)])
      error_message = "availability_zone_ids ${jsonencode(local.availability_zone_ids)} include IDs that are not available zones in ${local.aws_region} for this account. Available: ${jsonencode(self.zone_ids)} (aws ec2 describe-availability-zones --region ${local.aws_region})."
    }
    postcondition {
      condition     = var.az_count <= (length(local.availability_zone_ids) > 0 ? length(local.availability_zone_ids) : length(self.names))
      error_message = "az_count (${var.az_count}) exceeds the availability zones resolved in ${local.aws_region}: set more availability_zone_ids or a lower az_count."
    }
  }
}

locals {
  az_names_by_id = local.read_availability_zones ? zipmap(data.aws_availability_zones.available[0].zone_ids, data.aws_availability_zones.available[0].names) : {}
  availability_zones = (
    !local.read_availability_zones ? var.availability_zones :
    length(local.availability_zone_ids) > 0 ? [for id in local.availability_zone_ids : local.az_names_by_id[id]] :
    slice(sort(data.aws_availability_zones.available[0].names), 0, min(3, length(data.aws_availability_zones.available[0].names)))
  )
}
