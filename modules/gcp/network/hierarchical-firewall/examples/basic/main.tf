# Example: apply a hierarchical firewall policy to an organization with a rule
# that allows Google health checks and a catch-all that delegates everything
# else to the VPC firewall rules.

locals {
  org_id = "organizations/123456789012"
}

module "org_firewall" {
  source = "../../"

  parent      = local.org_id
  policy_name = "org-baseline"
  description = "Baseline security rules inherited by all projects in the org"

  rules = [
    # Allow Google health checker ingress to every VM under the org.
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
    # Not a deny: goto_next hands the remaining traffic to the VPC firewall
    # rules (and their implied deny-ingress).
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
