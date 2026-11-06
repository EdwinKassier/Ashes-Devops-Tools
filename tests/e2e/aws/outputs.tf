output "kms_key_arn" {
  description = "ARN of the per-run CMK created by modules/aws/data/kms-key."
  value       = module.kms.key_arn
}

output "archive_bucket_name" {
  description = "Name of the per-run Object Lock bucket created by modules/aws/data/log-archive-bucket."
  value       = module.archive.bucket_name
}

output "sink_bucket_name" {
  description = "Name of the per-run access-log / flow-log sink bucket."
  value       = aws_s3_bucket.sink.bucket
}

output "vpc_id" {
  description = "ID of the per-run VPC created by modules/aws/network/vpc."
  value       = module.vpc.vpc_id
}

output "observed" {
  description = "Values read back from the live AWS APIs after apply (what the e2e assertions check). Printed in the CI log for triage."
  value = {
    canary_sse          = data.aws_s3_object.canary.server_side_encryption
    canary_kms_key      = data.aws_s3_object.canary.sse_kms_key_id
    canary_lock_mode    = data.aws_s3_object.canary.object_lock_mode
    kms_key_state       = data.aws_kms_key.archive.key_state
    vpc_cidr            = data.aws_vpc.this.cidr_block
    private_subnet_cidr = data.aws_subnet.private.cidr_block
    s3_endpoint_state   = data.aws_vpc_endpoint.s3.state
  }
}
