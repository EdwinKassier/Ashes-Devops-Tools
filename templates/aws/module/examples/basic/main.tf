# Basic working example for the MODULE_NAME module.
# Calls the scaffold module at the repo-relative source path with the minimum
# required inputs. Run `terraform init && terraform validate` here to check it.

module "example" {
  source = "../../"

  name  = var.name
  value = "example-value"
}
