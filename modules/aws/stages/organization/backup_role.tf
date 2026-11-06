# Member-account AWS Backup service role (Workloads OU), deployed from the
# management account by a service-managed StackSet. It lives here, with the
# other org-wide role StackSets, so the least-privilege aws-backup management
# role needs no CloudFormation rights (a StackSet is an org-wide
# role-deployment primitive). aws-backup's BACKUP_POLICY names it with
# arn:aws:iam::$account:role/<backup_service_role_name>.

locals {
  backup_service_role_template = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "AWS Backup service role for the organization BACKUP_POLICY (managed by aws-organization)."
    Resources = {
      BackupServiceRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = var.backup_service_role_name
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect    = "Allow"
              Principal = { Service = "backup.amazonaws.com" }
              Action    = "sts:AssumeRole"
            }]
          }
          ManagedPolicyArns = [
            { "Fn::Sub" = "arn:$${AWS::Partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup" },
            { "Fn::Sub" = "arn:$${AWS::Partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores" },
          ]
        }
      }
    }
  })
}

resource "aws_cloudformation_stack_set" "backup_service_role" {
  count = var.create_backup_service_role ? 1 : 0

  name             = var.backup_service_role_stack_set_name
  description      = "AWS Backup service role for the organization BACKUP_POLICY in every Workloads-OU account."
  permission_model = "SERVICE_MANAGED"
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  template_body    = local.backup_service_role_template

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  managed_execution {
    active = true
  }

  operation_preferences {
    failure_tolerance_count = 0
    max_concurrent_count    = 10
    region_concurrency_type = "SEQUENTIAL"
  }

  lifecycle {
    ignore_changes = [administration_role_arn]
  }
}

resource "aws_cloudformation_stack_set_instance" "backup_service_role" {
  count = var.create_backup_service_role ? 1 : 0

  stack_set_name            = aws_cloudformation_stack_set.backup_service_role[0].name
  stack_set_instance_region = var.backup_service_role_region
  retain_stack              = false

  deployment_targets {
    organizational_unit_ids = [module.organization.ou_ids["Workloads"]]
  }

  operation_preferences {
    failure_tolerance_count = 0
    max_concurrent_count    = 10
  }
}
