# Resource-assertion tests for the aws/organization module.
#
# Asserts on configured attributes (feature_set) and on for_each keys derived
# from a variable, which ARE known at plan time under mock_provider. Provider-
# computed attributes (ids, arns) are deliberately not asserted on here.

mock_provider "aws" {}

run "org_enables_all_features_and_sra_ous" {
  command = plan

  assert {
    condition     = aws_organizations_organization.this.feature_set == "ALL"
    error_message = "Organization must enable ALL features"
  }

  assert {
    condition     = length(setintersection(toset(keys(aws_organizations_organizational_unit.top)), toset(["Security", "Infrastructure", "Workloads"]))) == 3
    error_message = "Foundational OUs Security, Infrastructure, Workloads must exist"
  }

  assert {
    condition     = length(keys(aws_organizations_organizational_unit.top)) == 8
    error_message = "All eight default top-level SRA OUs must be planned"
  }

  assert {
    condition     = contains(keys(aws_organizations_organizational_unit.child), "Workloads/Prod") && contains(keys(aws_organizations_organizational_unit.child), "Workloads/NonProd")
    error_message = "Default child OUs Workloads/Prod and Workloads/NonProd must exist"
  }

  assert {
    condition     = contains(aws_organizations_organization.this.enabled_policy_types, "RESOURCE_CONTROL_POLICY") && contains(aws_organizations_organization.this.enabled_policy_types, "BACKUP_POLICY")
    error_message = "RCP and backup policy types must be enabled"
  }
}
