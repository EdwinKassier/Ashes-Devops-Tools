# Example: the landing-zone hub network with the org-wide SSH/RDP-from-internet
# deny as a folder-level hierarchical firewall policy. Replace the placeholder
# project and folder IDs before use.

module "example" {
  source = "../../"

  project_id     = "myorg-hub-abc123"
  project_prefix = "myorg"
  region         = "us-central1"

  network = {
    name           = "hub-vpc-core"
    cidr_block     = "10.0.0.0/16"
    explicit_zones = ["us-central1-a", "us-central1-b", "us-central1-c"]
  }

  hierarchical_firewall_policies = {
    "policy-hub-shared" = {
      parent       = "folders/123456789001"
      associations = ["folders/123456789001"]
      rules = [{
        priority       = 500
        action         = "deny"
        direction      = "INGRESS"
        description    = "Deny RDP/SSH from Public Internet (Use IAP instead)"
        layer4_configs = [{ ip_protocol = "tcp", ports = ["22", "3389"] }]
        src_ip_ranges  = ["0.0.0.0/0"]
      }]
    }
  }
}
