# Example: create two firewall rules — one that allows internal health-check
# traffic from Google's health-check probers, and one that denies all other
# ingress from the internet to tagged instances.

locals {
  project_id = "my-workload-project"
  network    = "my-vpc"
}

# Allow health checks from GCP load-balancer prober ranges.
module "allow_health_checks" {
  source = "../../"

  project_id         = local.project_id
  firewall_rule_name = "allow-google-hc"
  network            = local.network
  direction          = "INGRESS"
  priority           = 900

  allow_rules = [
    { protocol = "tcp", ports = ["80", "443", "8080"] }
  ]

  # RFC 5737 documentation ranges used by GCP health checkers.
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]

  target_tags = ["backend"]
}

# Block inbound internet traffic to internal services.
module "deny_internet_ingress" {
  source = "../../"

  project_id         = local.project_id
  firewall_rule_name = "deny-internet-to-internal"
  network            = local.network
  direction          = "INGRESS"
  priority           = 1100

  deny_rules = [
    { protocol = "tcp", ports = [] },
    { protocol = "udp", ports = [] },
  ]

  source_ranges  = ["0.0.0.0/0"]
  target_tags    = ["internal-only"]
  enable_logging = true
}

output "health_check_rule_id" {
  value = module.allow_health_checks.firewall_rule_id
}
