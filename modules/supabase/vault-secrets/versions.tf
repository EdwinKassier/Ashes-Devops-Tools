terraform {
  required_version = ">= 1.17, < 2.0"

  # No providers: the module uses only the built-in terraform_data resource.
  # (Earlier versions used hashicorp/null; the moved blocks in main.tf migrate
  # that state. Terraform resolves hashicorp/null from existing state during the
  # one-time move, so callers with pre-existing state should keep null declared
  # in their root until the move has been applied — envs/saas does.)
}
