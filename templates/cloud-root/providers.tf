# Configure your cloud's default provider here. A workload root has ONE default
# provider; add aliased providers ONLY for fixed foundational accounts (never
# per workload — workloads fan out by workspace). See templates/aws-root/providers.tf
# for the concrete aws example, including the aliased assume-role pattern whose
# role ARNs come from the <cloud>-organization remote state.
#
# provider "azurerm" {
#   features {}
# }
