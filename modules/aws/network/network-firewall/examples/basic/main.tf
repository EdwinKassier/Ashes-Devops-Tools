# Basic working example for the aws/network-firewall module.
# Uses the module defaults (enabled, AWS-managed threat rule groups, two
# firewall subnets) and supplies the required inspection_vpc_id and
# log_bucket_name. Run `terraform init && terraform validate` here to check it.

module "network_firewall" {
  source = "../../"

  inspection_vpc_id = "vpc-0123456789abcdef0"
  log_bucket_name   = "example-firewall-log-bucket"
}
