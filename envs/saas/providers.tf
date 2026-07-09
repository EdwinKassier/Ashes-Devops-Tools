# Tokens are supplied via environment variables — no static config needed:
#   export SUPABASE_ACCESS_TOKEN="<your-supabase-token>"   # when enable_supabase = true
#   export VERCEL_API_TOKEN="<your-vercel-token>"          # when enable_vercel   = true
#
# There is intentionally NO provider "aws" or provider "google" here: this root
# never authenticates against a cloud, so a SaaS-only user needs no cloud creds.
provider "supabase" {}

provider "vercel" {}
