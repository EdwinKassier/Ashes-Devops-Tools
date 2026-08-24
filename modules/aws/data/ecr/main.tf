# Elastic Container Registry (ECR) repositories — the AWS parity counterpart to
# GCP's artifact-registry. Secure defaults: IMMUTABLE tags, scan-on-push, and
# encryption on (KMS when a key is supplied, else AES256). Repository and
# lifecycle policies are built with jsonencode() (never
# data.aws_iam_policy_document) so they stay plan-known under mock_provider.

locals {
  # Repositories that requested a lifecycle policy (either rule set).
  lifecycle_repos = {
    for name, r in var.repositories : name => r
    if r.expire_untagged_after_days != null || r.keep_last_tagged_images != null
  }
}

resource "aws_ecr_repository" "this" {
  # checkov:skip=CKV_AWS_51:Image tags are IMMUTABLE by default (var default), overridable per repo. Checkov cannot resolve the for_each optional() variable default, so it reads image_tag_mutability as unresolved — verified by plan_assertions (repo_secure_defaults).
  # checkov:skip=CKV_AWS_163:scan_on_push defaults to true (var default), overridable per repo. Same for_each/optional() resolution limitation; verified by plan_assertions.
  for_each = var.repositories

  name                 = each.key
  image_tag_mutability = each.value.image_tag_mutability
  force_delete         = each.value.force_delete
  tags                 = var.tags

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  encryption_configuration {
    encryption_type = each.value.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = each.value.kms_key_arn
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = local.lifecycle_repos
  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = concat(
      each.value.expire_untagged_after_days != null ? [{
        rulePriority = 1
        description  = "Expire untagged images older than ${each.value.expire_untagged_after_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = each.value.expire_untagged_after_days
        }
        action = { type = "expire" }
      }] : [],
      each.value.keep_last_tagged_images != null ? [{
        rulePriority = 2
        description  = "Keep only the last ${each.value.keep_last_tagged_images} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release", "prod"]
          countType     = "imageCountMoreThan"
          countNumber   = each.value.keep_last_tagged_images
        }
        action = { type = "expire" }
      }] : [],
    )
  })
}

resource "aws_ecr_repository_policy" "org" {
  for_each   = var.org_id != null ? var.repositories : {}
  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOrgPull"
      Effect    = "Allow"
      Principal = "*"
      Action = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
      ]
      Condition = {
        StringEquals = { "aws:PrincipalOrgID" = var.org_id }
      }
    }]
  })
}
