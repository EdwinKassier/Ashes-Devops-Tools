# Resource-assertion tests for the aws/vpc module.
#
# Asserts on configured attributes and on for_each-derived counts that are
# known at plan time under mock_provider. Provider-computed attributes (ids,
# arns) are not asserted on.

mock_provider "aws" {}

# region is required (no hard-coded default); runs may override it.
variables {
  region = "eu-west-2"
}

run "vpc_and_subnets_configured" {
  command = plan

  variables {
    region                   = "eu-west-2"
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames == true
    error_message = "VPC must enable DNS hostnames."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support == true
    error_message = "VPC must enable DNS support."
  }

  # Non-vacuous: with defaults az_count=2 and 3 tiers, 2 * 3 = 6 subnets.
  assert {
    condition     = length(aws_subnet.this) == var.az_count * length(keys(var.subnets))
    error_message = "One subnet must be created per tier per AZ (az_count * tier count)."
  }

  assert {
    condition     = length(aws_subnet.this) == 6
    error_message = "Defaults must produce exactly 6 subnets (2 AZs x 3 tiers)."
  }

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL"
    error_message = "Flow log must capture ALL traffic."
  }

  assert {
    condition     = length(aws_vpc_endpoint.gateway) == 2
    error_message = "Default gateway endpoints (s3, dynamodb) must both be created."
  }
}

run "routing_owned_by_module" {
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    name                     = "spoke-dev"
    create_internet_gateway  = true
    tags                     = { CostCenter = "platform" }
    routes = {
      private = [
        { destination_cidr_block = "0.0.0.0/0", transit_gateway_id = "tgw-000000000000abcd" },
        { destination_cidr_block = "10.0.0.0/8", transit_gateway_id = "tgw-000000000000abcd" },
      ]
    }
  }

  # One route table + association per tier per AZ (3 tiers x 2 AZs).
  assert {
    condition     = length(aws_route_table.this) == 6 && length(aws_route_table_association.this) == 6
    error_message = "The module must own one route table and association per tier per AZ."
  }

  assert {
    condition = alltrue([
      for k in ["public-0", "public-1", "private-0", "private-1", "isolated-0", "isolated-1"] : contains(keys(aws_route_table.this), k)
    ])
    error_message = "Route tables must be keyed <tier>-<az_index>."
  }

  # Gateway endpoints (2) attach to every NON-public tier route table (2 tiers x 2 AZs).
  assert {
    condition     = length(aws_vpc_endpoint_route_table_association.gateway) == 8
    error_message = "Gateway endpoints must be associated with the private and isolated route tables (2 services x 4 tables)."
  }

  assert {
    condition     = !anytrue([for k in keys(aws_vpc_endpoint_route_table_association.gateway) : strcontains(k, "|public-")])
    error_message = "Gateway endpoints must not be associated with public route tables by default."
  }

  # Caller routes are applied to every AZ table of the tier: 2 routes x 2 AZs.
  assert {
    condition     = length(aws_route.this) == 4
    error_message = "Each private-tier route must be created in every private AZ route table."
  }

  assert {
    condition = alltrue([
      for r in values(aws_route.this) : r.transit_gateway_id == "tgw-000000000000abcd"
    ])
    error_message = "Private-tier routes must target the transit gateway."
  }

  assert {
    condition     = aws_route.this["private-0|0.0.0.0/0"].destination_cidr_block == "0.0.0.0/0"
    error_message = "The private-0 table must carry the 0.0.0.0/0 TGW default route."
  }

  # IGW + public default route on each public AZ table.
  assert {
    condition     = length(aws_internet_gateway.this) == 1 && length(aws_route.public_internet) == 2
    error_message = "create_internet_gateway must create one IGW and a default route per public AZ table."
  }

  # Name is a variable and caller tags propagate.
  assert {
    condition     = aws_vpc.this.tags["Name"] == "spoke-dev" && aws_vpc.this.tags["CostCenter"] == "platform"
    error_message = "VPC Name must come from var.name and var.tags must be merged in."
  }

  assert {
    condition     = aws_route_table.this["private-0"].tags["Tier"] == "private" && aws_route_table.this["private-0"].tags["CostCenter"] == "platform"
    error_message = "Route tables must carry the Tier tag and caller tags."
  }
}

run "no_igw_by_default" {
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    gateway_endpoint_tiers   = ["private"]
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 0 && length(aws_route.public_internet) == 0 && length(aws_route.this) == 0
    error_message = "No IGW or routes must be created unless requested."
  }

  assert {
    condition     = length(aws_vpc_endpoint_route_table_association.gateway) == 4
    error_message = "gateway_endpoint_tiers must restrict endpoint associations to the chosen tiers."
  }
}

run "ipam_mode_passes_pool_and_explicit_cidr" {
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    ipam_pool_id             = "ipam-pool-0123456789abcdef0"
    ipam_allocation          = "explicit_cidr"
    cidr_block               = "10.20.0.0/16"
  }

  assert {
    condition     = aws_vpc.this.ipv4_ipam_pool_id == "ipam-pool-0123456789abcdef0" && aws_vpc.this.cidr_block == "10.20.0.0/16"
    error_message = "IPAM mode must pass the pool together with the explicit cidr_block"
  }

  assert {
    condition     = aws_vpc.this.ipv4_netmask_length == null
    error_message = "no netmask length may be sent alongside an explicit CIDR"
  }
}

run "static_mode_unchanged" {
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    cidr_block               = "10.20.0.0/16"
  }

  assert {
    condition     = aws_vpc.this.ipv4_ipam_pool_id == null && aws_vpc.this.cidr_block == "10.20.0.0/16" && aws_vpc.this.ipv4_netmask_length == null
    error_message = "static mode must set cidr_block only"
  }
}

run "existing_ipam_vpc_keeps_netmask_shape" {
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    ipam_pool_id             = "ipam-pool-0123456789abcdef0"
    cidr_block               = "10.20.0.0/16"
  }

  assert {
    condition     = aws_vpc.this.ipv4_ipam_pool_id == "ipam-pool-0123456789abcdef0" && aws_vpc.this.ipv4_netmask_length == 16
    error_message = "default IPAM allocation must keep the legacy pool + netmask_length shape (cidr_block stays unset; verified against the real provider)"
  }
}
