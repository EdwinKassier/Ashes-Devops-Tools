# Basic working example for the aws/access-analyzer-org module.
# Uses the module defaults. Run `terraform init && terraform validate` here to
# check it.
#
# In a real deployment this module is applied with the IAM Access Analyzer
# delegated-administrator provider; the delegated-admin registration itself is
# handled separately by the security-delegated-admin stage.

module "access_analyzer_org" {
  source = "../../"
}
