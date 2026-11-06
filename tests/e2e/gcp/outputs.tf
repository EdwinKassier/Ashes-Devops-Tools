output "kms_key_id" {
  description = "ID of the per-run CMEK crypto key."
  value       = google_kms_crypto_key.storage.id
}

output "data_bucket_name" {
  description = "Name of the CMEK-encrypted data bucket created by modules/gcp/cloud-storage."
  value       = module.storage.bucket_names["e2e"]
}

output "network_self_link" {
  description = "Self link of the per-run VPC."
  value       = module.vpc.self_link
}

output "subnet_self_link" {
  description = "Self link of the per-run subnet."
  value       = module.subnet.self_link
}

output "canary_secret_id" {
  description = "Fully qualified ID of the canary secret."
  value       = module.secrets.secret_ids[local.canary_secret_id]
}

output "observed" {
  description = "Values read back from the live GCP APIs after apply (what the e2e assertions check). Printed in the CI log for triage."
  value = {
    data_bucket_kms_key = try(data.google_storage_bucket.data.encryption[0].default_kms_key_name, null)
    logs_bucket_kms_key = try(data.google_storage_bucket.logs.encryption[0].default_kms_key_name, null)
    vpc_subnetworks     = data.google_compute_network.vpc.subnetworks_self_links
    subnet_cidr         = data.google_compute_subnetwork.app.ip_cidr_range
    secret_version      = data.google_secret_manager_secret_version.canary.name
  }
}
