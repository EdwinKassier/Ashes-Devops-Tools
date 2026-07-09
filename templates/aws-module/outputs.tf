# Every module must export at minimum:
#   - The ARN or ID of each primary resource created
#   - Any values downstream callers need to reference (names, URLs, endpoints)
#
# Use sensitive = true for values that should not appear in plan output
# (tokens, passwords). Never output raw secret material.
#
# Replace the stub outputs below with the actual outputs for your module.
# outputs.tf must NEVER be left empty — the PR checklist enforces this.

output "name" {
  description = "The name of the MODULE_NAME resource. Replace with the actual resource reference."
  # REPLACE: value = aws_RESOURCE_TYPE.main.name
  value = aws_ssm_parameter.example.name
}

output "arn" {
  description = "The ARN of the MODULE_NAME resource. Replace with the actual resource reference."
  # REPLACE: value = aws_RESOURCE_TYPE.main.arn
  value = aws_ssm_parameter.example.arn
}
