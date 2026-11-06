output "managed_secret_names" {
  description = "Sorted list of secret names managed by this module. Visible in plan output — useful for verifying the desired-state map without exposing values."
  value       = sort(nonsensitive(keys(var.secrets)))
}

output "bootstrap_trigger_id" {
  description = "Unique ID of the bootstrap terraform_data resource; changes when the bootstrap script is re-run."
  value       = terraform_data.bootstrap.id
}

output "reconcile_trigger_id" {
  description = "Unique ID of the reconcile terraform_data resource; changes when secrets are reconciled."
  value       = terraform_data.reconcile.id
}
