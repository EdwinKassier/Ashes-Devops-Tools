# Basic working example for the aws/route53-resolver module.
# Supplies the required vpc_id, org_arn, and query log destination, plus one
# FORWARD rule. Run `terraform init && terraform validate` here to check it.

module "route53_resolver" {
  source = "../../"

  name_prefix               = "org"
  vpc_id                    = "vpc-0123456789abcdef0"
  subnet_ids                = ["subnet-aaaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbbb"]
  org_arn                   = "arn:aws:organizations::111122223333:organization/o-exampleorgid"
  query_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"

  forward_rules = {
    corp = {
      domain_name = "corp.example.com"
      target_ips  = ["10.0.0.2", "10.0.1.2"]
    }
  }
}
