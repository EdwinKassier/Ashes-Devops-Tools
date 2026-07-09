terraform {
  required_version = "~> 1.9"

  required_providers {
    # Add your cloud's provider here, floored and capped to a major version.
    # Follow the aws-root example (>= X.Y.Z, < NEXT_MAJOR.0.0):
    #
    # azurerm = {
    #   source  = "hashicorp/azurerm"
    #   version = ">= 4.0.0, < 5.0.0"
    # }
  }
}
