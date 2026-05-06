# Example: apply a hierarchical firewall policy to an organization with rules
# that allow Google health checks and deny RFC-1918 egress to the internet.

locals {
  org_id = "organizations/123456789012"
}

module "org_firewall" {
  source = "../../"

  parent      = local.org_id
  policy_name = "org-baseline"
  description = "Baseline security rules inherited by all projects in the org"

  rules = [
    # Allow GCP health checker ingress to tagged instances.
    {
      priority    = 1000
      action      = "allow"
      direction   = "INGRESS"
      description = "Allow GCP health checker probes"
      layer4_configs = [
        { ip_protocol = "tcp", ports = ["80", "443"] }
      ]
      src_ip_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
    },
    # Default deny; remaining traffic falls through to VPC firewall rules.
    {
      priority    = 65534
      action      = "goto_next"
      direction   = "INGRESS"
      description = "Fall through to VPC-level rules"
      layer4_configs = [
        { ip_protocol = "all" }
      ]
      src_ip_ranges = ["0.0.0.0/0"]
    },
  ]

  # Attach the policy to all child folders and projects under the org.
  associations = [local.org_id]
}

output "policy_id" {
  description = "Resource ID of the hierarchical firewall policy"
  value       = module.org_firewall.id
}
