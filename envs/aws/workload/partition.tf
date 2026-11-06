# Partition of the default provider's account (aws, aws-us-gov, aws-cn).
data "aws_partition" "root" {}

locals {
  partition = can(regex("^aws(-[a-z]+)*$", data.aws_partition.root.partition)) ? data.aws_partition.root.partition : "aws"
}
