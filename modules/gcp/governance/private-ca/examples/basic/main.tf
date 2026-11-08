# Example: an ENTERPRISE-tier Certificate Authority Service pool with a
# self-signed ROOT CA for internal certificates: RSA 4096 key, 10-year
# lifetime, deletion protection on and the CAS deletion grace period kept.
#
# CAS bills per active CA. Set enable_ca = false to create only the pool and
# stage the CA for a later apply. Replace the placeholder values before use.
#
# Run `terraform init && terraform validate` here.

module "private_ca" {
  source = "../../"

  project_id   = "my-project-id"
  location     = "europe-west2"
  ca_pool_name = "org-internal-pool"
  name         = "org-root-ca"

  ca_type = "ROOT"
  tier    = "ENTERPRISE"

  subject = {
    organization = "Example Org"
    common_name  = "Example Org Internal Root CA"
  }

  key_algorithm = "RSA_PKCS1_4096_SHA256"
  lifetime      = "315360000s" # 10 years

  # Defaults, shown for clarity: guard the trust anchor against teardown.
  deletion_protection                    = true
  ignore_active_certificates_on_deletion = false
  skip_grace_period                      = false

  labels = {
    team = "platform"
  }
}
