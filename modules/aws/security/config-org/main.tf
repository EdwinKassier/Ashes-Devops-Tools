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

locals {
  use_service_linked_role    = var.config_role_arn == null
  create_service_linked_role = local.use_service_linked_role && var.create_service_linked_role
  create_aggregator_role     = !var.recorder_only && (var.aggregator_role_arn == null || var.aggregator_role_arn == "")

  # The recorder role: an explicit ARN, else the account's service-linked role
  # at its well-known path (created below, or pre-existing). Built from the
  # caller identity rather than the SLR resource so it is plan-known.
  config_role_arn = local.use_service_linked_role ? "arn:${var.partition}:iam::${coalesce(var.account_id, try(data.aws_caller_identity.current[0].account_id, null))}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig" : var.config_role_arn

  aggregator_role_arn = local.create_aggregator_role ? aws_iam_role.aggregator[0].arn : var.aggregator_role_arn
}

data "aws_caller_identity" "current" {
  count = local.use_service_linked_role && var.account_id == null ? 1 : 0
}

# AWS Config service-linked role (AWSServiceRoleForConfig): the AWS-recommended
# recorder identity. It is account-global, so one per account covers every
# per-Region recorder below.
resource "aws_iam_service_linked_role" "config" {
  count            = local.create_service_linked_role ? 1 : 0
  aws_service_name = "config.amazonaws.com"
  tags             = var.tags
}

# Organization aggregator role: trusted by config.amazonaws.com, with the AWS
# managed AWSConfigRoleForOrganizations policy (organizations:Describe*/List*).
resource "aws_iam_role" "aggregator" {
  count = local.create_aggregator_role ? 1 : 0
  name  = var.aggregator_role_name

  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "aggregator" {
  count      = local.create_aggregator_role ? 1 : 0
  role       = aws_iam_role.aggregator[0].name
  policy_arn = "arn:${var.partition}:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

resource "aws_config_configuration_recorder" "this" {
  # checkov:skip=CKV2_AWS_48:Recording all supported resource types IS the default —
  #   recording_group.all_supported = var.record_all_supported, which defaults to true.
  #   Checkov's graph check cannot resolve the variable-driven all_supported and flags
  #   the recorder even though the default posture records every supported type (plus
  #   global types in the home Region). The false toggle exists only as a documented
  #   cost lever for narrowing the recording group out-of-band.
  for_each = toset(var.aws_enabled_regions)
  name     = var.recorder_name
  region   = each.value
  role_arn = local.config_role_arn

  recording_group {
    all_supported = var.record_all_supported
    # Global resource types (IAM users, roles, policies, …) are global, so
    # recording them in every Region duplicates the same configuration items
    # once per Region — extra Config cost for no extra coverage. Record them in
    # the home Region only. Still gated on all_supported, since
    # include_global_resource_types is only valid when all_supported = true.
    include_global_resource_types = (each.value == var.home_region) && var.record_all_supported
  }

  # The service-linked role must exist before the recorder references it.
  depends_on = [aws_iam_service_linked_role.config]
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
    role_arn    = local.aggregator_role_arn
  }

  # IAM is eventually consistent: the managed policy must be attached before the
  # aggregator first assumes the role.
  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.aggregator]
}

resource "aws_config_organization_conformance_pack" "this" {
  for_each = var.recorder_only ? {} : var.conformance_packs
  name     = each.key

  template_body   = try(each.value.template_body, null)
  template_s3_uri = try(each.value.template_s3_uri, null)
}
