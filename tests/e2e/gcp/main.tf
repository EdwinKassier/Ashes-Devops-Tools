# Real-apply end-to-end fixture for the GCP primitives.
#
# Composes low-cost, project-scoped modules exactly as a stage would:
#   governance/kms (keyring) -> CMEK crypto key -> cloud-storage (CMEK buckets)
#   network/vpc -> network/subnet
#   data/secret-manager (container + one canary version)
# then READS THE RESULT BACK from the real APIs with data sources, so the
# assertions in e2e.tftest.hcl check what GCP actually stored rather than echoing
# inputs. `terraform test` destroys everything at the end of the run.
#
# Every name carries "e2e-<run_id>-<attempt>" so concurrent or re-run suites never
# collide. Cost: well under $1 per run (see docs/guides/sandbox-e2e.md).

locals {
  name = "e2e-${var.run_id}-${var.run_attempt}"

  # Canary payload: not a credential, just a value to prove the round trip.
  canary_secret_value = "e2e-canary-${var.run_id}-${var.run_attempt}"
  canary_secret_id    = "${local.name}-canary"
}

# The GCS service agent must hold encrypt/decrypt on the CMEK key before a bucket
# can use it. This data source also provisions the agent on first use.
data "google_storage_project_service_account" "gcs" {
  project = var.project_id
}

# ---------------------------------------------------------------------------
# KMS
# ---------------------------------------------------------------------------

# Keyring via the shared module. `keys = {}` on purpose: the module hard-codes
# `prevent_destroy = true` on its crypto keys (correct for production, fatal for a
# suite that must tear down), so the key is declared below instead. GCP keyrings
# cannot be deleted at all; destroy only drops them from state. They are free, which
# is why each run gets its own keyring name.
module "kms" {
  source = "../../../modules/gcp/governance/kms"

  project_id   = var.project_id
  keyring_name = local.name
  location     = var.region
  keys         = {}
}

resource "google_kms_crypto_key" "storage" {
  # checkov:skip=CKV_GCP_82:Ephemeral e2e key that must be destroyable; prevent_destroy would break the suite's teardown.
  name            = "storage"
  key_ring        = module.kms.keyring_id
  rotation_period = "7776000s"
  purpose         = "ENCRYPT_DECRYPT"

  # Shortest allowed window, so destroyed key material stops existing (and
  # costing) after one day.
  destroy_scheduled_duration = "86400s"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }
}

resource "google_kms_crypto_key_iam_member" "gcs_agent" {
  crypto_key_id = google_kms_crypto_key.storage.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = data.google_storage_project_service_account.gcs.member
}

# ---------------------------------------------------------------------------
# Cloud Storage (CMEK)
# ---------------------------------------------------------------------------

module "storage" {
  source = "../../../modules/gcp/cloud-storage"

  project_id         = var.project_id
  region             = var.region
  kms_key_name       = google_kms_crypto_key.storage.id
  log_retention_days = 1
  labels             = { "e2e-suite" = "gcp" }

  data_buckets = {
    e2e = {
      name_suffix                   = local.name
      force_destroy                 = true
      soft_delete_retention_seconds = 0
    }
  }

  # The bucket create call fails if the service agent cannot use the key yet.
  depends_on = [google_kms_crypto_key_iam_member.gcs_agent]
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

module "vpc" {
  source = "../../../modules/gcp/network/vpc"

  project_id                 = var.project_id
  vpc_name                   = local.name
  enable_deletion_protection = false
}

module "subnet" {
  source = "../../../modules/gcp/network/subnet"

  project_id    = var.project_id
  subnet_name   = "${local.name}-app"
  ip_cidr_range = "10.250.0.0/24"
  region        = var.region
  network       = module.vpc.id
}

# ---------------------------------------------------------------------------
# Secret Manager
# ---------------------------------------------------------------------------

module "secrets" {
  source = "../../../modules/gcp/data/secret-manager"

  project_id                 = var.project_id
  enable_deletion_protection = false

  secrets = {
    (local.canary_secret_id) = {
      labels      = { "e2e-suite" = "gcp" }
      replication = { user_managed_regions = [var.region] }
    }
  }

  secret_values = {
    (local.canary_secret_id) = local.canary_secret_value
  }
}

# ---------------------------------------------------------------------------
# Read-back from the real APIs. depends_on defers each read until after the
# module has been applied, so these see the live resource, not the plan.
# ---------------------------------------------------------------------------

data "google_storage_bucket" "data" {
  name = module.storage.bucket_names["e2e"]

  depends_on = [module.storage]
}

data "google_storage_bucket" "logs" {
  name = module.storage.logs_bucket_name

  depends_on = [module.storage]
}

data "google_compute_network" "vpc" {
  project = var.project_id
  name    = module.vpc.name

  depends_on = [module.subnet]
}

data "google_compute_subnetwork" "app" {
  project = var.project_id
  region  = var.region
  name    = module.subnet.name

  depends_on = [module.subnet]
}

data "google_secret_manager_secret_version" "canary" {
  project = var.project_id
  secret  = module.secrets.secret_short_ids[local.canary_secret_id]

  depends_on = [module.secrets]
}
