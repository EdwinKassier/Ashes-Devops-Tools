# Module resources go here.
#
# Guidelines:
#   - One resource type per logical grouping; use locals for computed values.
#   - Add lifecycle { prevent_destroy = true } via a terraform_data guard (not
#     directly on the resource) when deletion protection is user-controlled.
#   - Use data sources only when required — prefer passing values as variables.
#   - checkov:skip annotations require a justification comment on the same line.
