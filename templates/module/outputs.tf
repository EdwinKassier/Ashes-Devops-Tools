# Every module must export at minimum:
#   - The ID or self_link of each primary resource created
#   - Any values downstream callers need to reference (names, URLs, emails)
#
# Use sensitive = true for values that should not appear in plan output
# (tokens, passwords). Never output raw secret material.

# output "example_id" {
#   description = "The ID of the example resource"
#   value       = google_example_resource.main.id
# }
