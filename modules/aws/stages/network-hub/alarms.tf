# Network alarms (ARC-15): transit gateway blackhole drops, NAT port
# exhaustion and VPN tunnel state. Alarm actions publish to one SNS topic: the
# caller's alarm_sns_topic_arn, else a topic this stage creates in the network
# account (the security-notifications topic lives in another account, and a
# cross-account publish needs a topic policy and key grant this stage cannot
# write). A created topic notifies nobody until a subscriber exists, so
# alarm_subscriber_emails subscribes addresses to it. The stage cannot judge
# whether the estate is production: the aws-network root refuses a production
# plan without a real subscriber.
#
# Metric names, namespaces and dimensions (AWS documentation, checked 2026-11-12):
#   AWS/TransitGateway PacketDropCountBlackhole, dimension TransitGateway
#     https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-cloudwatch-metrics.html
#   AWS/NATGateway ErrorPortAllocation, dimension NatGatewayId (zonal gateway)
#     https://docs.aws.amazon.com/vpc/latest/userguide/metrics-dimensions-nat-gateway.html
#   AWS/VPN TunnelState, dimension VpnId
#     https://docs.aws.amazon.com/vpn/latest/s2svpn/monitoring-cloudwatch-vpn.html
#
# Network Firewall has no alarm here: see docs/known-gaps.md.

locals {
  # One alarm per NAT gateway (one per AZ). Keys come from the static AZ index.
  nat_alarms = {
    for k, ng in aws_nat_gateway.this : "nat-port-allocation-errors-${k}" => {
      namespace           = "AWS/NATGateway"
      metric_name         = "ErrorPortAllocation"
      statistic           = "Sum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 0
      evaluation_periods  = 2
      dimensions          = { NatGatewayId = ng.id }
      alarm_description   = "NAT gateway ${ng.id} could not allocate a source port in two consecutive periods: too many concurrent connections, and spoke egress through it is failing."
    }
  }

  # Both segments with spokes attached carry deliberate blackhole routes
  # (segment isolation), so a stray prod to nonprod packet counts here. Only
  # drops that last three periods alarm: a probe is brief, a missing route is not.
  tgw_alarms = {
    "tgw-blackhole-drops" = {
      namespace           = "AWS/TransitGateway"
      metric_name         = "PacketDropCountBlackhole"
      statistic           = "Sum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 0
      evaluation_periods  = 3
      dimensions          = { TransitGateway = module.transit_gateway.tgw_id }
      alarm_description   = "The hub transit gateway dropped packets on a blackhole route for 15 minutes. Segment isolation routes cause this on purpose for prod and nonprod traffic; sustained drops mean a spoke or segment is sending to a range it must not reach, or a route points at a deleted attachment."
    }
  }

  # TunnelState is 1 when every tunnel is up and below 1 when at least one is
  # not. A missing metric means no data from the VPN: treated as down.
  vpn_alarms = var.enable_vpn ? {
    "vpn-tunnel-not-up" = {
      namespace           = "AWS/VPN"
      metric_name         = "TunnelState"
      statistic           = "Minimum"
      comparison_operator = "LessThanThreshold"
      threshold           = 1
      evaluation_periods  = 2
      treat_missing_data  = "breaching"
      dimensions          = { VpnId = module.vpn[0].vpn_connection_id }
      alarm_description   = "At least one tunnel of the hub Site-to-Site VPN is not up. With one tunnel left there is no redundancy; with none, on-premises connectivity is lost. If the on-premises device brings up only one tunnel, this alarm stays on: configure both."
    }
  } : {}
}

module "network_alarms" {
  source = "../../ops/cloudwatch"

  name_prefix      = "network-hub"
  alarms           = merge(local.nat_alarms, local.tgw_alarms, local.vpn_alarms)
  create_sns_topic = var.alarm_sns_topic_arn == null
  sns_topic_arn    = var.alarm_sns_topic_arn
  tags             = var.tags
}

# Email subscribers on the topic this stage creates (each must confirm).
resource "aws_sns_topic_subscription" "alarm_email" {
  for_each = var.alarm_sns_topic_arn == null ? toset(var.alarm_subscriber_emails) : toset([])

  topic_arn = module.network_alarms.sns_topic_arn
  protocol  = "email"
  endpoint  = each.value
}
