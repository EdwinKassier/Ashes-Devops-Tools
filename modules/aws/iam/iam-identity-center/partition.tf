# Partition of the Identity Center account, so the commercial
# arn:aws:iam::aws:policy/... defaults resolve correctly in GovCloud / China.
data "aws_partition" "current" {}

locals {
  partition = can(regex("^aws(-[a-z]+)*$", data.aws_partition.current.partition)) ? data.aws_partition.current.partition : "aws"
}
