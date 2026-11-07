# CloudTrail delegated administrator (opt-in, enable_cloudtrail_delegated_admin).
#
# Registered by aws-organization (the phase-0 management role) through
# CloudTrail itself rather than the generic Organizations API: only the
# CloudTrail call creates the AWSServiceRoleForCloudTrail and
# AWSServiceRoleForCloudTrailEventContext service-linked roles. Security tooling
# then creates and manages the organization trail. The trail is still owned by
# the management account (its ARN carries the management account ID), but its
# manager is a member account, so the deny-tamper SCP applies to every change
# made to it.
#
# aws-security registers the same service principal through
# security-delegated-admin while the flag is off; with it on that module drops
# it from its default set. An estate that already has the registration imports
# it here (aws.adopt.cloudtrail_delegated_admin_account_id in the
# aws-organization root) rather than creating it, because the API rejects a
# second registration (AccountRegisteredException). See
# docs/runbooks/aws-cloudtrail-delegated-admin-migration.md.

resource "aws_cloudtrail_organization_delegated_admin_account" "this" {
  count = var.enable_cloudtrail_delegated_admin ? 1 : 0

  account_id = module.account["security_tooling"].account_id

  # Trusted access for cloudtrail.amazonaws.com is enabled by module.organization.
  depends_on = [module.organization]
}
