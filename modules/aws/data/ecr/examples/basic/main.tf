# Basic working example for the aws/ecr module.
# Creates one immutable, scan-on-push container repository encrypted with a
# customer-managed KMS key, with a lifecycle policy that expires untagged images
# and caps tagged history. Accounts in the organization get pull access through
# an org-scoped repository policy. Run `terraform init && terraform validate`
# here to check it.
#
# The KMS key ARN and organization ID are placeholders: replace them with your
# own.

module "ecr" {
  source = "../../"

  repositories = {
    "orders-api" = {
      image_tag_mutability       = "IMMUTABLE"
      scan_on_push               = true
      kms_key_arn                = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
      expire_untagged_after_days = 14
      keep_last_tagged_images    = 50
    }
  }

  org_id = "o-abc123xyz0"

  tags = {
    environment = "shared"
  }
}
