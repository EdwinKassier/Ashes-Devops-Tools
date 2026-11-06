# Partition of the provider's account (aws, aws-us-gov, aws-cn), so every ARN
# this module builds is valid outside the commercial partition. Under a mock
# provider the data source returns a random string, so it falls back to "aws".
data "aws_partition" "current" {}

locals {
  partition = can(regex("^aws(-[a-z]+)*$", data.aws_partition.current.partition)) ? data.aws_partition.current.partition : "aws"
}
