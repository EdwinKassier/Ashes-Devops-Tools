# Basic example for the aws/security/config-recorder-stackset module: recorders
# in every account under the org root except security tooling, two Regions.
# Run `terraform init && terraform validate` here to check it.

module "config_recorder_stackset" {
  source = "../../"

  target_ou_ids               = ["r-abcd"]
  security_tooling_account_id = "222222222222"
  aws_enabled_regions         = ["eu-west-2", "eu-west-1"]
  home_region                 = "eu-west-2"
  log_archive_bucket_name     = "acme-org-log-archive"
}
