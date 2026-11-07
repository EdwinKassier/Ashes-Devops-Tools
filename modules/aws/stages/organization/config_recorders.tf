# Org-wide AWS Config recorders, owned by aws-organization.
#
#   * module.org_config_recorders — a service-managed StackSet deploying the
#     recorder and delivery channel to every member account under the org root
#     EXCEPT security tooling, which keeps its own aggregator recorder
#     (stages/security). Auto-deployment covers accounts vended later.
#   * module.management_config_recorder — service-managed StackSets never deploy
#     to the management account, so it gets a direct recorder (recorder-only).
#
# Both sit behind enable_org_config_recorders (default false): their delivery
# target, the log-archive bucket and its Config bucket policy, comes from
# aws-security, which applies after aws-organization. aws-security needs no
# CloudFormation rights: this stage owns every org StackSet.
#
# The recorder SCP (enable_config_recorder_scp, module.policies) is the last
# step of docs/runbooks/aws-config-recorder-migration.md.

locals {
  security_tooling_account_id = try(module.account["security_tooling"].account_id, null)
}

module "org_config_recorders" {
  source = "../../security/config-recorder-stackset"
  count  = var.enable_org_config_recorders ? 1 : 0

  target_ou_ids                          = [module.organization.roots_id]
  security_tooling_account_id            = local.security_tooling_account_id
  aws_enabled_regions                    = var.aws_enabled_regions
  home_region                            = var.org_trail_home_region
  log_archive_bucket_name                = var.log_archive_bucket_name
  migration_failure_tolerance_percentage = var.org_config_recorders_failure_tolerance_percentage

  # Trusted access for StackSets is enabled by module.organization.
  depends_on = [module.organization]
}

module "management_config_recorder" {
  source = "../../security/config-org"
  count  = var.enable_org_config_recorders ? 1 : 0

  recorder_only              = true
  aws_enabled_regions        = var.aws_enabled_regions
  home_region                = var.org_trail_home_region
  log_archive_bucket         = var.log_archive_bucket_name
  create_service_linked_role = var.create_management_config_service_linked_role
  account_id                 = module.organization.management_account_id
  partition                  = var.partition
  aggregator_role_arn        = "" # unused in recorder_only mode
}
