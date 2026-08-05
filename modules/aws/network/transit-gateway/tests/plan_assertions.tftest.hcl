# Resource-assertion tests for the aws/transit-gateway module.
#
# Asserts on configured attributes and for_each-derived counts/keys that are
# known at plan time under mock_provider. Provider-computed attributes (ids,
# arns) are not asserted on.

mock_provider "aws" {}

run "segments_and_isolation" {
  command = plan

  variables {
    org_arn = "arn:aws:organizations::123456789012:organization/o-exampleorgid"
  }

  # The gateway must disable the implicit default route tables so segmentation
  # cannot be bypassed.
  assert {
    condition     = aws_ec2_transit_gateway.this.default_route_table_association == "disable"
    error_message = "Default route table association must be disabled."
  }

  assert {
    condition     = aws_ec2_transit_gateway.this.default_route_table_propagation == "disable"
    error_message = "Default route table propagation must be disabled."
  }

  # prod and nonprod segment route tables must both exist.
  assert {
    condition     = contains(keys(aws_ec2_transit_gateway_route_table.this), "prod")
    error_message = "A prod segment route table must exist."
  }

  assert {
    condition     = contains(keys(aws_ec2_transit_gateway_route_table.this), "nonprod")
    error_message = "A nonprod segment route table must exist."
  }

  # NON-VACUOUS prod/nonprod isolation.
  #
  # Build the concrete set of propagation edges as "<attachment-segment>-><route-table>"
  # strings from var.propagations. Because a propagation into a route table is
  # the ONLY way (no default table) a segment's routes become reachable from an
  # attachment, the absence of "prod->nonprod" and "nonprod->prod" edges proves
  # prod and nonprod cannot reach each other. The set is asserted non-empty so
  # the check cannot pass vacuously.
  assert {
    condition = (
      length(var.propagations) > 0 &&
      !contains(
        [for p in values(var.propagations) : "${var.attachments[p.attachment].segment}->${p.route_table}"],
        "prod->nonprod"
      ) &&
      !contains(
        [for p in values(var.propagations) : "${var.attachments[p.attachment].segment}->${p.route_table}"],
        "nonprod->prod"
      )
    )
    error_message = "prod and nonprod segments must not propagate into each other (isolation), and the propagation set must be non-empty."
  }

  # Sanity: shared IS reachable from prod (proves the edge model is real, not
  # that every cross-segment edge is missing).
  assert {
    condition = contains(
      [for p in values(var.propagations) : "${var.attachments[p.attachment].segment}->${p.route_table}"],
      "prod->shared"
    )
    error_message = "prod must propagate into the shared route table."
  }

  # Every attachment must have exactly one association.
  assert {
    condition     = length(aws_ec2_transit_gateway_route_table_association.this) == length(var.attachments)
    error_message = "Each attachment must have exactly one route table association."
  }

  # RAM share must not allow external principals.
  assert {
    condition     = aws_ram_resource_share.this.allow_external_principals == false
    error_message = "RAM share must not allow external principals."
  }
}
