output "psc_ip_address" {
  description = "Internal IP address for the PSC endpoint — create an A record for 'googleapis.com' pointing here"
  value       = module.psc_google_apis.address
}
