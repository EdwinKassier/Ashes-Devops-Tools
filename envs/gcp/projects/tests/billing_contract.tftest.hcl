# The organization contract's billing_account may be the bare ID (what
# gcp-organization emits: data.google_billing_account.id) or the
# billingAccounts/<ID> resource name. The projects stage accepts only the bare
# ID, so the root strips the prefix. Here the real projects stage plans (no
# override_module) from a config-file contract that carries the prefixed form.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  landing_zone_config_path = "tests/fixtures/landing-zone-billing-prefixed.yaml"
}

run "billing_account_prefix_is_stripped" {
  command = plan

  assert {
    condition     = local.organization_contract.billing_account == "000000-111111-222222"
    error_message = "The config-file contract billing_account must be normalised to the bare ID"
  }

  assert {
    condition = alltrue([
      for k in ["dev-host", "prod-host", "shared-hub"] : module.projects.projects[k].billing_account == "000000-111111-222222"
    ])
    error_message = "Every host project must link the bare billing account ID"
  }
}

# The same prefixed form through the organization_contract variable.
run "billing_account_prefix_is_stripped_from_variable" {
  command = plan

  variables {
    organization_contract = {
      billing_account = "billingAccounts/000000-111111-222222"
      folders = {
        shared = { id = "100", name = "folders/100", display_name = "Shared" }
        dev    = { id = "111", name = "folders/111", display_name = "Development" }
        prod   = { id = "222", name = "folders/222", display_name = "Production" }
      }
      tag_values = {
        environment-dev              = "tagValues/1"
        environment-prod             = "tagValues/2"
        data-classification-internal = "tagValues/902"
      }
    }
  }

  assert {
    condition     = module.projects.projects["dev-host"].billing_account == "000000-111111-222222"
    error_message = "A billingAccounts/ billing_account in organization_contract must reach the projects stage as the bare ID"
  }
}
