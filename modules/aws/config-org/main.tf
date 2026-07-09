# AWS Config for the SRA landing zone: multi-Region recorders plus the
# organization aggregator and (optional) conformance packs.
#
# Two modes:
#   recorder_only = false  -> home-account recorders in every enabled Region
#                             PLUS the org-wide aggregator and conformance packs.
#                             Used by the C16 aws-config stage in the home account.
#   recorder_only = true   -> just the per-Region recorder/delivery-channel/status
#                             for a single workload account. Used by the
#                             aws-workload stage. The aggregator and conformance
#                             packs are count/for_each gated off.
#
# Brand-new-account recorders are otherwise bootstrapped out-of-band by a Config
# StackSet; this module manages recorders for accounts already under management.
#
# Per-Region resources fan out with for_each over aws_enabled_regions using the
# provider-level `region` argument (AWS provider v6 enhanced Region support), so
# no per-Region provider aliases are required.

resource "aws_config_configuration_recorder" "this" {
  for_each = toset(var.aws_enabled_regions)
  name     = var.recorder_name
  region   = each.value
  role_arn = var.config_role_arn

  recording_group {
    all_supported = var.record_all_supported
    # include_global_resource_types is only valid when all_supported = true;
    # gate it so a false all_supported config does not trip provider validation.
    include_global_resource_types = var.record_all_supported
  }
}

resource "aws_config_delivery_channel" "this" {
  for_each       = toset(var.aws_enabled_regions)
  name           = var.delivery_channel_name
  region         = each.value
  s3_bucket_name = var.log_archive_bucket

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  for_each   = toset(var.aws_enabled_regions)
  name       = aws_config_configuration_recorder.this[each.key].name
  region     = each.value
  is_enabled = true

  # Runtime ordering: the delivery channel must exist before the recorder can be
  # started, otherwise StartConfigurationRecorder fails.
  depends_on = [aws_config_delivery_channel.this]
}

resource "aws_config_configuration_aggregator" "org" {
  count = var.recorder_only ? 0 : 1
  name  = var.aggregator_name

  organization_aggregation_source {
    all_regions = true
    role_arn    = var.aggregator_role_arn
  }
}

resource "aws_config_organization_conformance_pack" "this" {
  for_each = var.recorder_only ? {} : var.conformance_packs
  name     = each.key

  template_body   = try(each.value.template_body, null)
  template_s3_uri = try(each.value.template_s3_uri, null)
}
