# Configure your cloud's default provider here. A workload root has ONE default
# provider; add aliased providers ONLY for fixed foundational accounts (never
# per workload — workloads fan out by workspace). See templates/aws/root/providers.tf
# for the concrete aws example, including the aliased assume-role pattern whose
# role ARNs come from the <cloud>-organization remote state.
#
# Every provider in a root writes the four keys that the mandatory OPA policy
# require_labels checks (policies/opa/require_labels.rego): ManagedBy,
# Environment, CostCenter and Owner on AWS (default_tags), managed-by,
# environment, cost-center and owner on GCP (default_labels). Take CostCenter
# and Owner from org.cost_center and org.owner in config/landing-zone.yaml.
#
# provider "azurerm" {
#   features {}
# }
