# REAL-APPLY suite: no mock_provider. Applies into a disposable sandbox project
# and asserts on values read back from the live GCP APIs. `terraform test`
# destroys every resource it created when the file finishes (pass or fail);
# the sandbox-e2e workflow adds a label-scoped safety-net cleanup on top.
#
# Inputs come from TF_VAR_project_id / TF_VAR_region / TF_VAR_run_id /
# TF_VAR_run_attempt. Run via `make e2e-gcp` or .github/workflows/sandbox-e2e.yml.
# Never run this against a landing-zone project.

run "apply_gcp_primitives" {
  command = apply

  # --- KMS + CMEK storage ----------------------------------------------------

  assert {
    condition     = try(data.google_storage_bucket.data.encryption[0].default_kms_key_name, "") == google_kms_crypto_key.storage.id
    error_message = "Data bucket is not encrypted by default with the per-run CMEK key."
  }

  assert {
    condition     = try(data.google_storage_bucket.logs.encryption[0].default_kms_key_name, "") == google_kms_crypto_key.storage.id
    error_message = "Logs bucket is not encrypted by default with the per-run CMEK key."
  }

  assert {
    condition     = google_kms_crypto_key.storage.key_ring == module.kms.keyring_id && module.kms.keyring_location == var.region
    error_message = "CMEK key is not in the keyring created by modules/gcp/governance/kms in the requested region."
  }

  assert {
    condition     = data.google_storage_bucket.data.public_access_prevention == "enforced" && data.google_storage_bucket.data.uniform_bucket_level_access
    error_message = "Data bucket must have public access prevention enforced and uniform bucket-level access."
  }

  assert {
    condition     = try(data.google_storage_bucket.data.versioning[0].enabled, false)
    error_message = "Data bucket versioning is not enabled."
  }

  assert {
    condition     = try(data.google_storage_bucket.data.logging[0].log_bucket, "") == module.storage.logs_bucket_name
    error_message = "Data bucket access logging does not point at the module's logs bucket."
  }

  assert {
    condition     = lower(data.google_storage_bucket.data.location) == lower(var.region)
    error_message = "Data bucket was not created in the requested region."
  }

  # --- Network ---------------------------------------------------------------

  assert {
    condition     = data.google_compute_subnetwork.app.ip_cidr_range == "10.250.0.0/24"
    error_message = "Subnet CIDR read back from GCP does not match the requested range."
  }

  assert {
    condition     = data.google_compute_subnetwork.app.network == module.vpc.self_link
    error_message = "Subnet is not attached to the VPC created by modules/gcp/network/vpc."
  }

  assert {
    condition     = data.google_compute_subnetwork.app.private_ip_google_access
    error_message = "Private Google Access is not enabled on the subnet (module default is true)."
  }

  assert {
    condition     = contains(data.google_compute_network.vpc.subnetworks_self_links, module.subnet.self_link)
    error_message = "VPC read back from GCP does not list the subnet."
  }

  # --- Secret Manager --------------------------------------------------------

  assert {
    condition     = data.google_secret_manager_secret_version.canary.secret_data == local.canary_secret_value
    error_message = "Canary secret version read back from Secret Manager does not match what was written."
  }

  assert {
    condition     = data.google_secret_manager_secret_version.canary.enabled
    error_message = "Canary secret version is not enabled."
  }
}
