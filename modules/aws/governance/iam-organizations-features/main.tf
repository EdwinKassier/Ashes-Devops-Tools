# Centralized root-access management for the SRA landing zone.
#
# Enables organization-wide IAM features that let the management account
# centrally manage root credentials for MEMBER accounts. Once enabled, member
# accounts no longer retain their own root credentials; privileged root actions
# are brokered through the management account instead.
#
# This resource is run from the management-account provider and requires
# iam.amazonaws.com trusted access on the organization (enabled by the
# aws/organization module's aws_service_access_principals).

resource "aws_iam_organizations_features" "this" {
  enabled_features = var.enabled_features
}
