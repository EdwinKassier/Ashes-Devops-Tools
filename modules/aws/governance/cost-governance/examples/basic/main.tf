# Basic working example for the aws/cost-governance module.
# One org-monthly budget that emails at 80% actual spend, the DIMENSIONAL/SERVICE
# anomaly monitor + subscription, and the three default cost-allocation tags.
# Set real recipients: without them nobody is told when a budget or anomaly
# alert fires. Run `terraform init && terraform validate` here to check it.

module "cost_governance" {
  source = "../../"

  budgets = {
    org-monthly = {
      limit_amount      = "1000"
      threshold_percent = 80
      emails            = ["finops@example.com"]
    }
  }

  anomaly_email = "finops@example.com"
}
