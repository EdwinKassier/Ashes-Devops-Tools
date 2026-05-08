variable "vpn_shared_secret" {
  description = <<-EOT
    Pre-shared key for VPN tunnel authentication. Treat as a password.
    Pass via environment variable to avoid committing secrets:
      export TF_VAR_vpn_shared_secret="$(openssl rand -base64 32)"
      terraform apply
    Or use Secret Manager: reference the secret ID in a data source and pass
    the resolved value to this variable.
  EOT
  type        = string
  sensitive   = true
}
