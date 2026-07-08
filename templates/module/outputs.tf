# Every module must export at minimum:
#   - The ID or self_link of each primary resource created
#   - Any values downstream callers need to reference (names, URLs, emails)
#
# Use sensitive = true for values that should not appear in plan output
# (tokens, passwords). Never output raw secret material.
#
# Replace the stub outputs below with the actual outputs for your module.
# outputs.tf must NEVER be left empty — the PR checklist enforces this.

output "id" {
  description = "The unique identifier of the MODULE_NAME resource. Replace with the actual resource reference."
  # REPLACE: value = google_RESOURCE_TYPE.main.id
  value = google_project_service.example.id
}

output "name" {
  description = "The name of the MODULE_NAME resource. Replace with the actual resource reference."
  # REPLACE: value = google_RESOURCE_TYPE.main.name
  value = google_project_service.example.service
}
