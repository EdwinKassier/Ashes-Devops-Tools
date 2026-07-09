# Module resources go here.
#
# Guidelines:
#   - One resource type per logical grouping; use locals for computed values.
#   - Add lifecycle { prevent_destroy = true } via a terraform_data guard (not
#     directly on the resource) when deletion protection is user-controlled.
#   - Use data sources only when required — prefer passing values as variables.
#   - checkov:skip annotations require a justification comment on the same line.
#   - Do NOT declare a provider {} block here — the root module supplies the
#     configured aws provider (see examples/aliased for the cross-account
#     providers = { aws = aws.member } pattern).
#
# EXAMPLE RESOURCE — replace with your module's real resource(s). Kept minimal
# and dependency-free so `terraform plan` succeeds under mock_provider with
# nothing but name set, giving tests/plan_assertions.tftest.hcl a real planned
# attribute to assert on.

# Scaffold example resource — replace when cloning this template.
resource "aws_ssm_parameter" "example" {
  name  = var.name
  type  = "String"
  value = var.value
}
