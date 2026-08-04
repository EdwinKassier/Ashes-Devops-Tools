# Resource-assertion example for the MODULE_NAME module.
#
# variables_validation.tftest.hcl only proves inputs are accepted/rejected —
# it never proves the module actually plans the resource you think it does.
# Every module must ALSO have at least one command=plan test that asserts on
# a planned resource or output attribute, like this one. See CONTRIBUTING.md
# "Testing" for the full requirement and the vacuous-alltrue([]) warning.
#
# INSTRUCTIONS FOR USE:
#   1. Replace MODULE_NAME with your module's name throughout.
#   2. Replace google_project_service.example with your module's real resource
#      address(es) and assert on an attribute that actually depends on input.
#   3. If the assertion iterates a for_each/count resource, also assert
#      length(...) > 0 so an empty set can't make the assertion vacuously pass.
#   4. Run: cd modules/your-module && terraform test

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id = "mock-project-id"
  # Add other required variables here
}

run "example_service_plans_with_expected_attributes" {
  command = plan

  assert {
    condition     = google_project_service.example.project == "mock-project-id"
    error_message = "example service must be planned against the supplied project_id"
  }

  assert {
    condition     = google_project_service.example.service == "compute.googleapis.com"
    error_message = "example service must request the compute.googleapis.com API"
  }

  assert {
    condition     = output.name == "compute.googleapis.com"
    error_message = "the name output must surface the planned service name"
  }
}
