# Basic working example for the aws/rds-aurora module.
# Creates a two-instance (writer + reader) Aurora PostgreSQL cluster in private
# subnets, encrypted with a customer-managed KMS key. RDS generates and manages
# the master password in Secrets Manager (also CMK-encrypted), so no password
# appears in this configuration or in Terraform state. IAM database
# authentication, deletion protection and a final snapshot stay at their secure
# defaults. Run `terraform init && terraform validate` here to check it.
#
# Every ID and ARN below is a placeholder: replace them with your own private
# subnets (in distinct AZs), database security group and CMK.

module "rds_aurora" {
  source = "../../"

  name          = "dev-orders-db"
  database_name = "orders"

  kms_key_id                    = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
  master_user_secret_kms_key_id = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"

  subnet_ids         = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
  security_group_ids = ["sg-0ccccccccccccccc1"]

  backup_retention_period = 14

  tags = {
    environment = "dev"
  }
}
