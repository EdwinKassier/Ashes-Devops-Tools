/**
 * Private CA Module - Certificate Authority Service (CAS)
 *
 * GCP parity counterpart to the AWS ACM Private CA module
 * (modules/aws/data/private-ca). Provisions a CA pool and a single
 * Certificate Authority (ROOT or SUBORDINATE) for issuing private
 * (internal) certificates.
 *
 * Like ACM PCA, Certificate Authority Service bills a fixed monthly
 * charge per CA in the ENTERPRISE tier from the moment the CA exists,
 * so CA creation is gated behind enable_ca (default true — the pool is
 * always created, the CA can be staged out).
 */

locals {
  # ROOT CAs are self-signed in CAS; SUBORDINATE CAs are signed by a parent.
  ca_type_map = {
    ROOT        = "SELF_SIGNED"
    SUBORDINATE = "SUBORDINATE"
  }
  ca_resource_type = local.ca_type_map[var.ca_type]
}

# CA Pool — the container that groups one or more CAs and sets the tier
# and publishing options shared by the CAs it holds.
resource "google_privateca_ca_pool" "this" {
  name     = var.ca_pool_name
  location = var.location
  project  = var.project_id
  tier     = var.tier

  publishing_options {
    publish_ca_cert = true
    publish_crl     = true
  }

  labels = var.labels
}

# Certificate Authority — the signing CA itself. Gated behind enable_ca so
# the pool can be provisioned ahead of (or without) an active, billing CA.
resource "google_privateca_certificate_authority" "this" {
  count = var.enable_ca ? 1 : 0

  certificate_authority_id = var.name
  location                 = var.location
  project                  = var.project_id
  pool                     = google_privateca_ca_pool.this.name
  type                     = local.ca_resource_type
  lifetime                 = var.lifetime

  config {
    subject_config {
      subject {
        organization = var.subject.organization
        common_name  = var.subject.common_name
      }
    }

    x509_config {
      ca_options {
        is_ca = true
      }
      key_usage {
        base_key_usage {
          cert_sign = true
          crl_sign  = true
        }
        extended_key_usage {
          server_auth = true
        }
      }
    }
  }

  key_spec {
    algorithm = var.key_algorithm
  }

  # Safe-by-default lifecycle toggles. deletion_protection defaults true so a
  # CA cannot be destroyed by an unguarded apply; the CAS-specific toggles
  # default to their safe values (keep active certs, honour the grace period).
  deletion_protection                    = var.deletion_protection
  ignore_active_certificates_on_deletion = var.ignore_active_certificates_on_deletion
  skip_grace_period                      = var.skip_grace_period

  labels = var.labels
}
