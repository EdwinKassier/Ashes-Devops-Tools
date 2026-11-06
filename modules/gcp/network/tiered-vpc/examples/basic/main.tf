# Example: a three-tier VPC with the baseline tier firewall, pinned to two
# zones. Replace the placeholder project ID before use.

module "example" {
  source = "../../"

  project_id = "my-network-project"
  name       = "example-vpc"
  region     = "us-central1"
  cidr_block = "10.30.0.0/16"
  zones      = ["us-central1-a", "us-central1-b"]
}
