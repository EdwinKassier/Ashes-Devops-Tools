# Basic working example for the aws/vpc-endpoints module.
# Creates the default set of centralized interface endpoints in a hub VPC with
# an org-scoped policy, plus a shared private hosted zone for split-horizon DNS.
# Run `terraform init && terraform validate` here to check it.

module "vpc_endpoints" {
  source = "../../"

  vpc_id             = "vpc-0123456789abcdef0"
  region             = "eu-west-2"
  org_id             = "o-abcde12345"
  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  security_group_ids = ["sg-0123456789abcdef0"]

  private_hosted_zone_name = "internal.example.com"
}
