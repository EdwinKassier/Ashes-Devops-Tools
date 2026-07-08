# Regression test: the auth payload must use the provider's canonical JSON key
# `jwt_exp` (UpdateAuthConfigBody struct tag). The provider unmarshals `auth`
# with lenient decoding, so a misnamed key like `jwt_expiry` would be silently
# dropped and the configured expiry never applied.

mock_provider "supabase" {}

variables {
  project_ref = "abcdefghijklmnopqrst"
}

run "auth_uses_jwt_exp_key" {
  command = plan

  variables {
    jwt_expiry          = 1800
    password_min_length = 14
    mailer_autoconfirm  = true
    disable_signup      = true
  }

  # jsondecode round-trips the planned auth JSON so we assert on real keys.
  assert {
    condition     = jsondecode(supabase_settings.this.auth).jwt_exp == 1800
    error_message = "auth payload must send jwt_exp (the provider's canonical key), carrying var.jwt_expiry"
  }

  assert {
    condition     = !contains(keys(jsondecode(supabase_settings.this.auth)), "jwt_expiry")
    error_message = "auth payload must not use the non-existent jwt_expiry key (silently dropped by the provider)"
  }

  assert {
    condition     = jsondecode(supabase_settings.this.auth).password_min_length == 14 && jsondecode(supabase_settings.this.auth).mailer_autoconfirm == true
    error_message = "auth payload must retain the correct password_min_length and mailer_autoconfirm keys"
  }
}
