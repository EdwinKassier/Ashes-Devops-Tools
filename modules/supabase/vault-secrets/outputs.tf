output "managed_secret_names" {
  description = "Sorted list of secret names managed by this module. Visible in plan output — useful for verifying the desired-state map without exposing values."
  value       = sort(nonsensitive(keys(var.secrets)))
}
