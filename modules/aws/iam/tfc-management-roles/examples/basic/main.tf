# Basic example: run from the MANAGEMENT account (as aws-organization does).
module "tfc_management_roles" {
  source = "../../"

  tfc_organization = var.tfc_organization
  tfc_project      = "landing-zone-aws"
}
