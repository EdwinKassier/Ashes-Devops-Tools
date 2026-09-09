# Plan assertions for the supabase/environment composite module: verify the composite
# wires the child project's identity through to its outputs. Child modules are
# overridden (their data-source postconditions can't evaluate under mock).
# All runs use mock_provider so no Supabase credentials are required.

mock_provider "supabase" {}

variables {
  organization_id   = "abcdefghijklmnop"
  project_name      = "my-app-qa"
  database_password = "exactly-sixteen!!"
  region            = "eu-west-2"
}

run "composite_outputs_wired_from_children" {
  command = plan

  override_module {
    target  = module.project
    outputs = { id = "abcdefghijklmnopqrst", name = "my-app-qa", database_password = "exactly-sixteen!!" }
  }
  override_module {
    target  = module.settings
    outputs = { project_ref = "abcdefghijklmnopqrst" }
  }

  assert {
    condition     = output.project_id == "abcdefghijklmnopqrst"
    error_message = "Composite project_id output must come from the child project module."
  }

  assert {
    condition     = output.project_name == var.project_name
    error_message = "Composite project_name output must reflect the caller-supplied project_name."
  }
}
