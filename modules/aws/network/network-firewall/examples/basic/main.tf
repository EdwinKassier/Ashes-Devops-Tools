# Basic working example for the aws/network-firewall module, configured as the
# network-hub stage uses it: endpoints in the inspection VPC's firewall subnets
# (one per AZ), AWS-managed threat rule groups, and HOME_NET set to the org
# supernet so the rules match spoke traffic, not only the inspection VPC.
# Run `terraform init && terraform validate` here to check it.

module "network_firewall" {
  source = "../../"

  inspection_vpc_id   = "vpc-0123456789abcdef0"
  firewall_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  home_net_cidrs      = ["10.0.0.0/8"]
  log_bucket_name     = "example-firewall-log-bucket"
}
