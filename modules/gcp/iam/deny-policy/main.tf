# IAM Deny policies — a coarse, allow-independent backstop that blocks specific
# permissions for specific principals regardless of the roles they hold. IAM
# always evaluates deny before allow, so a matching deny wins. Recommended by
# Google's enterprise-foundations guidance as the defense-in-depth complement to
# Organization Policy constraints (org policy restricts resource *config*; deny
# policies restrict principal *actions*). See docs/known-gaps.md (G9).

resource "google_iam_deny_policy" "this" {
  for_each = { for p in var.deny_policies : p.name => p }

  name         = each.value.name
  parent       = var.parent
  display_name = each.value.display_name

  dynamic "rules" {
    for_each = each.value.rules
    content {
      description = rules.value.description
      deny_rule {
        denied_principals     = rules.value.denied_principals
        denied_permissions    = rules.value.denied_permissions
        exception_principals  = rules.value.exception_principals
        exception_permissions = rules.value.exception_permissions

        dynamic "denial_condition" {
          for_each = rules.value.denial_condition != null ? [rules.value.denial_condition] : []
          content {
            expression  = denial_condition.value.expression
            title       = denial_condition.value.title
            description = denial_condition.value.description
          }
        }
      }
    }
  }
}
