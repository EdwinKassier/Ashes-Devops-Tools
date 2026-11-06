# Basic working example for the tfc-oidc-baseline module.
# Run from the MANAGEMENT account (call_as = SELF). Binds two member accounts to
# their TFC workspaces with exact names. Run `terraform init && terraform validate`
# here to check it.

module "tfc_oidc_baseline" {
  source = "../../"

  tfc_organization = var.tfc_organization
  tfc_project      = "landing-zone"

  account_bindings = {
    network         = { account_id = "444444444444", workspaces = ["aws-network"] }
    shared_services = { account_id = "555555555555", workspaces = ["aws-identity", "aws-shared-services"] }
  }

  target_ou_ids = {
    Infrastructure = "ou-abcd-infra0000"
  }
}
