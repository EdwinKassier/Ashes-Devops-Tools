# Tokens are supplied via environment variables — no static config needed:
#   export SUPABASE_ACCESS_TOKEN="<your-supabase-token>"   # only when enable_supabase = true
#   export VERCEL_API_TOKEN="<your-vercel-token>"          # only when enable_vercel   = true
#
# There is intentionally NO provider "aws" or provider "google" here: this root
# never authenticates against a cloud, so a SaaS-only user needs no cloud creds.
#
# ── Single-provider mode (Supabase-only / Vercel-only) ───────────────────────
# A provider block cannot be conditional, and Terraform configures every provider
# a root declares — even when all of its resources are at count = 0. Both
# providers fail at configure time when their token is empty, so without the
# placeholders below a Supabase-only plan would demand VERCEL_API_TOKEN and vice
# versa.
#
# When a feature is DISABLED its provider gets an inert, syntactically valid
# placeholder token. Neither provider calls its API while configuring (verified
# with a real local-backend `terraform plan` against supabase/supabase 1.9.1 and
# vercel/vercel 4.8.2 — see docs/architecture/provider-selection.md), and with
# the feature off no resource or data source uses the provider, so the
# placeholder is never sent anywhere. It is NOT a credential.
#
# When a feature is ENABLED the attribute is null, so the provider reads its
# token from the environment exactly as before.
#
# Caveat: disabling a feature whose resources are still in state makes Terraform
# refresh/destroy them with the placeholder, which fails with an auth error
# (fail-closed, nothing is changed). Destroy them first with the feature still
# enabled, then flip the flag. See provider-selection.md.
#
# The placeholders are inline literals (sbp_ + 40 zeros; 24 zeros), not locals:
# the plan-time execution guard (policies/opa/no_plan_time_code_execution*.rego
# and scripts/check-plan-time-exec.py) allows exactly these literals in these
# arguments, and it cannot check what a local evaluates to.
provider "supabase" {
  access_token = local.enable_supabase ? null : "sbp_disabled_placeholder"
}

provider "vercel" {
  api_token = local.enable_vercel ? null : "000000000000000000000000"
}
