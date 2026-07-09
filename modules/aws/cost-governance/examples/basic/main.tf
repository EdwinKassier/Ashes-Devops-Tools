# Basic working example for the aws/cost-governance module.
# Uses the module defaults (a single org-monthly budget, the DIMENSIONAL/SERVICE
# anomaly monitor + subscription, and the three default cost-allocation tags).
# Run `terraform init && terraform validate` here to check it.

module "cost_governance" {
  source = "../../"
}
