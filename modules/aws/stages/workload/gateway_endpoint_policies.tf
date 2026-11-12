# Gateway endpoint policies (ARC-2).
#
# The spoke's S3 and DynamoDB gateway endpoints route that traffic straight to
# the service, past the hub egress firewall and its domain allowlist. With the
# default (full-access) endpoint policy, a workload can read from or write to
# any bucket or table in any AWS account. enable_gateway_endpoint_policies
# (the aws-workload root turns it on for production) limits both endpoints:
#
#   - AllowOrganizationResources: the service, only on resources whose owner
#     account is in this organization (aws:ResourceOrgID). The IAM guide lists
#     aws:ResourceOrgID among the keys to use "in VPC endpoint policies to
#     restrict which resources can be accessed from your networks" (Establish
#     permissions guardrails using data perimeters, checked 2026-11-12). It is a
#     global key, "included in the request context only if the account that
#     owns the resource is a member of an organization"; the unsupported-action
#     list in the global condition keys reference names no S3 or DynamoDB
#     action (checked 2026-11-12). The AWS data-perimeter examples use the same
#     condition in their S3 and default endpoint policies.
#   - AllowAwsServicePrincipals: requests that AWS services make with their
#     own service principal (aws:PrincipalIsAWSService), as in the AWS
#     data-perimeter endpoint policy examples.
#   - AllowAwsOwnedAndListedObjectReads (S3 only): s3:GetObject on the
#     AWS-owned buckets the landing zone's own workloads need, plus
#     gateway_endpoint_extra_s3_arns. Exact names, never a region wildcard (the
#     Systems Manager guide warns that wildcards "could provide access to S3
#     buckets that you don't intend to grant access to").
#
# Bucket names (all checked 2026-11-12):
#   - ECR image layers: arn:aws:s3:::prod-<region>-starport-layer-bucket/*
#     (Amazon ECR User Guide, "Minimum Amazon S3 Bucket Permissions for Amazon
#     ECR").
#   - Amazon Linux: AL2023 al2023-repos-<region>-de612dc2, AL2
#     amazonlinux.<region>.amazonaws.com and amazonlinux-2-repos-<region>
#     (Amazon EMR Management Guide, "Sample policies for private subnets that
#     access Amazon S3").
#   - SSM Agent: aws-windows-downloads-<region>, amazon-ssm-<region>,
#     aws-ssm-<region>, <region>-birdwatcher-prod, patch-baseline-snapshot-*
#     (Systems Manager User Guide, "SSM Agent communications with AWS managed
#     S3 buckets").
#   - Patch Manager: aws-patch-manager-<region>-<suffix> and the regions whose
#     patch-baseline-snapshot bucket has a suffix (Systems Manager User Guide,
#     "Reference: Amazon S3 buckets for patching operations"). The suffix maps
#     below copy that page. A region missing from the map gets no Patch
#     Manager bucket: add it through gateway_endpoint_extra_s3_arns.

locals {
  # Partition from the region name (the stage has no partition data source in
  # every configuration). AWS documents the bucket names for the aws partition.
  endpoint_partition = (
    startswith(var.aws_region, "us-gov-") ? "aws-us-gov" :
    startswith(var.aws_region, "cn-") ? "aws-cn" :
    startswith(var.aws_region, "eusc-") ? "aws-eusc" : "aws"
  )

  # aws-patch-manager-<region>-<suffix> (Linux and Windows Server).
  patch_manager_bucket_suffix = {
    "us-east-2"      = "552881074"
    "us-east-1"      = "1970c647d"
    "us-west-1"      = "8badb4304"
    "us-west-2"      = "34d7f99f8"
    "af-south-1"     = "bdd5f65a9"
    "ap-east-1"      = "632356271"
    "ap-south-2"     = "32f4b4128"
    "ap-southeast-3" = "aa48fc462"
    "ap-southeast-4" = "01e2c40d3"
    "ap-south-1"     = "cb7c62ff9"
    "ap-northeast-3" = "67373598a"
    "ap-northeast-2" = "10467995c"
    "ap-southeast-1" = "7fdfd9ef7"
    "ap-southeast-2" = "17283a275"
    "ap-northeast-1" = "4849fa78f"
    "ca-central-1"   = "3148e69e3"
    "ca-west-1"      = "9e3a4b2f9"
    "eu-central-1"   = "9163fdaaf"
    "eu-west-1"      = "5522fb710"
    "eu-west-2"      = "902a2bc74"
    "eu-south-1"     = "c52f3f594"
    "eu-west-3"      = "29bf85721"
    "eu-south-2"     = "a4cf248b1"
    "eu-north-1"     = "795879e9b"
    "eu-central-2"   = "184ce43c8"
    "il-central-1"   = "e221cb57b"
    "me-south-1"     = "a53fc9dce"
    "me-central-1"   = "2932f2f80"
    "sa-east-1"      = "ddf4b6a09"
    "ap-east-2"      = "5a64b2916"
    "ap-southeast-5" = "dcb42f3e3"
    "ap-southeast-6" = "df0d3a7f2"
    "ap-southeast-7" = "c707c017a"
    "mx-central-1"   = "396b275ad"
  }

  # Regions whose patch-baseline-snapshot bucket carries a suffix; every other
  # region uses patch-baseline-snapshot-<region>.
  patch_baseline_snapshot_suffix = {
    "af-south-1"     = "tbxdb5b9"
    "ap-south-2"     = "50209442"
    "ap-southeast-3" = "be0a3174"
    "ap-southeast-4" = "dc6f76ce"
    "eu-south-2"     = "df2c9d70"
    "me-south-1"     = "uduvl7q8"
    "ap-east-2"      = "8947749e"
    "ap-southeast-6" = "62f446f2"
    "ap-southeast-7" = "1699f14f"
    "mx-central-1"   = "ed0da79c"
  }

  aws_owned_bucket_names = compact([
    "prod-${var.aws_region}-starport-layer-bucket",
    "al2023-repos-${var.aws_region}-de612dc2",
    "amazonlinux.${var.aws_region}.amazonaws.com",
    "amazonlinux-2-repos-${var.aws_region}",
    "aws-windows-downloads-${var.aws_region}",
    "amazon-ssm-${var.aws_region}",
    "aws-ssm-${var.aws_region}",
    "${var.aws_region}-birdwatcher-prod",
    join("-", compact(["patch-baseline-snapshot", var.aws_region, lookup(local.patch_baseline_snapshot_suffix, var.aws_region, "")])),
    contains(keys(local.patch_manager_bucket_suffix), var.aws_region) ? "aws-patch-manager-${var.aws_region}-${local.patch_manager_bucket_suffix[var.aws_region]}" : "",
  ])

  aws_owned_object_arns = concat(
    [for b in local.aws_owned_bucket_names : "arn:${local.endpoint_partition}:s3:::${b}/*"],
    var.gateway_endpoint_extra_s3_arns,
  )

  gateway_endpoint_base_statements = {
    for svc in ["s3", "dynamodb"] : svc => [
      {
        Sid       = "AllowOrganizationResources"
        Effect    = "Allow"
        Principal = "*"
        Action    = "${svc}:*"
        Resource  = "*"
        Condition = { StringEquals = { "aws:ResourceOrgID" = var.organization_id } }
      },
      {
        Sid       = "AllowAwsServicePrincipals"
        Effect    = "Allow"
        Principal = "*"
        Action    = "${svc}:*"
        Resource  = "*"
        Condition = { Bool = { "aws:PrincipalIsAWSService" = "true" } }
      },
    ]
  }

  # {} when off: the vpc module then sends no policy (AWS full access).
  gateway_endpoint_policies = var.enable_gateway_endpoint_policies ? {
    s3 = jsonencode({
      Version = "2012-10-17"
      Statement = concat(local.gateway_endpoint_base_statements["s3"], [{
        Sid       = "AllowAwsOwnedAndListedObjectReads"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = local.aws_owned_object_arns
      }])
    })
    dynamodb = jsonencode({
      Version   = "2012-10-17"
      Statement = local.gateway_endpoint_base_statements["dynamodb"]
    })
  } : {}
}

check "patch_manager_bucket_known_for_region" {
  assert {
    condition     = !var.enable_gateway_endpoint_policies || contains(keys(local.patch_manager_bucket_suffix), var.aws_region) || length(var.gateway_endpoint_extra_s3_arns) > 0
    error_message = "Gateway endpoint policies are on, but ${var.aws_region} has no known Patch Manager bucket (aws-patch-manager-<region>-<suffix>). Patch scans and installs through the S3 gateway endpoint will fail. Add the bucket from the Systems Manager guide 'Reference: Amazon S3 buckets for patching operations' to gateway_endpoint_extra_s3_arns."
  }
}
