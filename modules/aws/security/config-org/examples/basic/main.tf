# Basic working example for the aws/config-org module.
# Home-account mode: recorders in every enabled Region plus the org aggregator.
# Run `terraform init && terraform validate` here to check it.

module "config_org" {
  source = "../../"

  # config_role_arn / aggregator_role_arn omitted: the module creates the
  # AWSServiceRoleForConfig service-linked role and the org aggregator role.
  log_archive_bucket = "ashes-org-log-archive"

  aws_enabled_regions = ["eu-west-2", "eu-west-1"]
}
