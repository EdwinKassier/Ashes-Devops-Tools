terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.46.0, < 7.0.0"

      # The stage runs in ONE workload account. The default provider covers the
      # in-account, in-region resources; the us_east_1 alias is threaded into the
      # optional edge-security module whose CloudFront/WAF/ACM resources must live
      # in us-east-1 regardless of the workload's home region.
      configuration_aliases = [aws.us_east_1]
    }
  }
}
