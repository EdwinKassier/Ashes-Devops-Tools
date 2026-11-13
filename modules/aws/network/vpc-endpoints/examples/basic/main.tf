# Basic working example for the aws/vpc-endpoints module, configured as the
# network-hub stage uses it: centralized interface endpoints in the hub egress
# VPC with an org-scoped policy, a module-owned security group that admits
# HTTPS from the org supernet, and each endpoint's regional name served from a
# shared private hosted zone so spoke VPCs resolve the central endpoints.
# Run `terraform init && terraform validate` here to check it.

module "vpc_endpoints" {
  source = "../../"

  vpc_id     = "vpc-0123456789abcdef0"
  region     = "eu-west-2"
  org_id     = "o-abcde12345"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]

  allowed_cidrs             = ["10.0.0.0/8"]
  enable_shared_private_dns = true

  private_hosted_zone_name = "internal.example.com"
}
