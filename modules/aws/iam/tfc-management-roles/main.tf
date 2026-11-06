# tfc-management-roles
#
# Per-workspace, least-privilege Terraform Cloud roles in the MANAGEMENT
# (payer) account for the roots that need management-account API calls besides
# aws-organization: aws-security (org CloudTrail, delegated-admin registration,
# management break-glass role) and aws-backup (the BACKUP_POLICY org policy).
#
# Why: without this, every management-default root shares the one phase-0
# management admin role, and the management account sits outside every SCP. A
# reviewed-looking change to envs/aws/backup could then assume
# OrganizationAccountAccessRole into every member account. Each role here
# trusts exactly one workspace and one run phase (exact sub, StringEquals), and
# every apply role explicitly denies the org-takeover actions it never needs.
#
# The roles are created by the aws-organization root (which runs as the phase-0
# management role); tfc-admin reads their ARNs from its outputs.

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id

  aud_key = "${var.tfc_hostname}:aud"
  sub_key = "${var.tfc_hostname}:sub"

  oidc_provider_arn = coalesce(
    var.oidc_provider_arn,
    "arn:${local.partition}:iam::${local.account_id}:oidc-provider/${var.tfc_hostname}",
  )

  phases = ["plan", "apply"]

  roles = {
    for pair in setproduct(keys(var.workspaces), local.phases) : "${pair[0]}:${pair[1]}" => {
      workspace = pair[0]
      phase     = pair[1]
      name      = "${var.role_name_prefix}${pair[0]}-${pair[1]}"
    }
  }

  # Org-takeover actions no management-default workspace other than
  # aws-organization ever needs. Explicit deny: an attached broad policy (or a
  # future edit to the allow list) cannot reintroduce them.
  org_takeover_deny = {
    Sid    = "DenyOrgTakeover"
    Effect = "Deny"
    Action = [
      "organizations:CreateAccount",
      "organizations:CloseAccount",
      "organizations:MoveAccount",
      "organizations:RemoveAccountFromOrganization",
      "organizations:InviteAccountToOrganization",
      "organizations:LeaveOrganization",
      "organizations:DeleteOrganization",
      "organizations:CreateOrganizationalUnit",
      "organizations:DeleteOrganizationalUnit",
      "organizations:UpdateOrganizationalUnit",
      "account:*",
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      # Same identity-provider set as the tfc-oidc-baseline boundary's
      # DenyNewIdentityProviders (asserted equal by the tests): no new trust
      # anchor and no repointing of an existing one.
      "iam:CreateOpenIDConnectProvider",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:CreateSAMLProvider",
      "iam:UpdateSAMLProvider",
    ]
    Resource = "*"
  }

  # The management credentials must never pivot into member accounts: only
  # break-glass reaches OrganizationAccountAccessRole.
  no_member_pivot_deny = {
    Sid      = "DenyMemberAccountPivot"
    Effect   = "Deny"
    Action   = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
    Resource = [for n in var.member_pivot_role_names : "arn:${local.partition}:iam::*:role/${n}"]
  }

  # No workspace may edit the management roles (its own or a sibling's), nor
  # the phase-0 roles.
  self_protection_deny = {
    Sid    = "DenyManagementRoleTampering"
    Effect = "Deny"
    Action = [
      "iam:AttachRolePolicy",
      "iam:DeleteRole",
      "iam:DeleteRolePermissionsBoundary",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:PutRolePolicy",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:TagRole",
      "iam:UntagRole",
    ]
    Resource = concat(
      ["arn:${local.partition}:iam::${local.account_id}:role/${var.role_name_prefix}*"],
      [for n in var.protected_role_names : "arn:${local.partition}:iam::${local.account_id}:role/${n}"],
      [for n in var.protected_role_names : "arn:${local.partition}:iam::${local.account_id}:role/*/${n}"],
    )
  }

  # Built-in apply permissions per known workspace. A workspace not listed
  # here must supply apply_policy_json.
  builtin_apply_statements = {
    "aws-security" = [
      {
        Sid    = "DelegatedAdminRegistration"
        Effect = "Allow"
        Action = [
          "organizations:Describe*",
          "organizations:List*",
          "organizations:RegisterDelegatedAdministrator",
          "organizations:DeregisterDelegatedAdministrator",
          "organizations:EnableAWSServiceAccess",
          "organizations:DisableAWSServiceAccess",
          "guardduty:EnableOrganizationAdminAccount",
          "guardduty:DisableOrganizationAdminAccount",
          "guardduty:ListOrganizationAdminAccounts",
          "securityhub:EnableOrganizationAdminAccount",
          "securityhub:DisableOrganizationAdminAccount",
          "securityhub:ListOrganizationAdminAccounts",
          "macie2:EnableOrganizationAdminAccount",
          "macie2:DisableOrganizationAdminAccount",
          "macie2:ListOrganizationAdminAccounts",
          "inspector2:EnableDelegatedAdminAccount",
          "inspector2:DisableDelegatedAdminAccount",
          "inspector2:ListDelegatedAdminAccounts",
          "detective:EnableOrganizationAdminAccount",
          "detective:DisableOrganizationAdminAccount",
          "detective:ListOrganizationAdminAccount",
          "fms:AssociateAdminAccount",
          "fms:DisassociateAdminAccount",
          "fms:GetAdminAccount",
          "iam:CreateServiceLinkedRole",
        ]
        Resource = "*"
      },
      {
        # The organization trail and its CloudWatch Logs / SNS / KMS wiring.
        # Destructive trail and key actions are denied below (break-glass only).
        Sid      = "OrganizationTrail"
        Effect   = "Allow"
        Action   = ["cloudtrail:*", "logs:*", "sns:*", "cloudwatch:*Alarm*", "cloudwatch:Describe*", "kms:*"]
        Resource = "*"
      },
      {
        # IAM writes ONLY on the trail's CloudWatch delivery role
        # (<trail>-cloudwatch-delivery). Any wider IAM write in the management
        # account (outside every SCP) is an org takeover: create a role, attach
        # AdministratorAccess, assume it, then OrganizationAccountAccessRole
        # everywhere. The management break-glass role is therefore NOT managed
        # through this role (keep create_break_glass = false, or apply it as
        # the phase-0 role).
        Sid    = "TrailDeliveryRoleOnly"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
          "iam:TagRole", "iam:UntagRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
        ]
        Resource = ["arn:${local.partition}:iam::${local.account_id}:role/${var.security_trail_role_pattern}"]
      },
      {
        Sid       = "PassTrailDeliveryRoleToCloudTrail"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = ["arn:${local.partition}:iam::${local.account_id}:role/${var.security_trail_role_pattern}"]
        Condition = { StringEquals = { "iam:PassedToService" = "cloudtrail.amazonaws.com" } }
      },
      {
        # Stopping or deleting the org trail, or destroying its keys, blinds the
        # whole organization: break-glass only.
        Sid      = "DenyTrailAndKeyDestruction"
        Effect   = "Deny"
        Action   = ["cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:DeleteImportedKeyMaterial"]
        Resource = "*"
      },
    ]
    "aws-backup" = [
      {
        Sid      = "OrgRead"
        Effect   = "Allow"
        Action   = ["organizations:Describe*", "organizations:List*", "iam:CreateServiceLinkedRole"]
        Resource = "*"
      },
      {
        # Backup policies only: every policy write is conditioned on the type.
        Sid    = "BackupPolicyOnly"
        Effect = "Allow"
        Action = [
          "organizations:CreatePolicy",
          "organizations:UpdatePolicy",
          "organizations:DeletePolicy",
          "organizations:AttachPolicy",
          "organizations:DetachPolicy",
          "organizations:EnablePolicyType",
        ]
        Resource  = "*"
        Condition = { StringEquals = { "organizations:PolicyType" = "BACKUP_POLICY" } }
      },
      {
        # Tagging takes no PolicyType condition; scope it by the policy ARN,
        # which embeds the type (policy/o-*/backup_policy/p-*).
        Sid      = "TagBackupPolicies"
        Effect   = "Allow"
        Action   = ["organizations:TagResource", "organizations:UntagResource", "organizations:ListTagsForResource"]
        Resource = ["arn:${local.partition}:organizations::${local.account_id}:policy/o-*/backup_policy/p-*"]
      },
      {
        Sid      = "BackupServiceAccess"
        Effect   = "Allow"
        Action   = ["organizations:EnableAWSServiceAccess", "organizations:DisableAWSServiceAccess"]
        Resource = "*"
        Condition = {
          StringEquals = { "organizations:ServicePrincipal" = ["backup.amazonaws.com"] }
        }
      },
    ]
  }

  apply_policies = {
    for ws, w in var.workspaces : ws => w.apply_policy_json != null ? w.apply_policy_json : jsonencode({
      Version = "2012-10-17"
      Statement = concat(
        local.builtin_apply_statements[ws],
        [local.org_takeover_deny, local.no_member_pivot_deny, local.self_protection_deny],
      )
    })
  }

  # Plan roles: ReadOnlyAccess minus data-plane reads, like the member
  # tfc-plan roles (a speculative plan runs PR code as this role).
  plan_data_read_deny = {
    Sid    = "DenyDataPlaneReads"
    Effect = "Deny"
    Action = [
      "s3:GetObject", "s3:GetObjectVersion", "secretsmanager:GetSecretValue", "ssm:GetParameter",
      "ssm:GetParameters", "ssm:GetParametersByPath", "kms:Decrypt", "logs:GetLogEvents",
      "logs:FilterLogEvents", "logs:StartQuery", "cloudtrail:LookupEvents", "dynamodb:GetItem",
      "dynamodb:Query", "dynamodb:Scan", "sqs:ReceiveMessage",
    ]
    Resource = "*"
  }

  guard_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [local.org_takeover_deny, local.no_member_pivot_deny, local.self_protection_deny, local.plan_data_read_deny]
  })
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "this" {
  for_each = local.roles

  name                 = each.value.name
  description          = "Terraform Cloud ${upper(each.value.phase)} role for workspace ${each.value.workspace} (management account, least privilege)."
  max_session_duration = var.max_session_duration
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "TfcWorkloadIdentity"
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          (local.aud_key) = "aws.workload.identity"
          (local.sub_key) = "organization:${var.tfc_organization}:project:${coalesce(var.workspaces[each.value.workspace].project, var.tfc_project)}:workspace:${each.value.workspace}:run_phase:${each.value.phase}"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "read_only" {
  for_each = local.roles

  role       = aws_iam_role.this[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

# The same org-takeover / member-pivot / self-protection denies on the PLAN
# role too: read-only managed policies change, explicit denies do not.
resource "aws_iam_role_policy" "plan_guard" {
  for_each = { for k, r in local.roles : k => r if r.phase == "plan" }

  name   = "tfc-plan-guard"
  role   = aws_iam_role.this[each.key].id
  policy = local.guard_policy
}

resource "aws_iam_role_policy" "apply" {
  for_each = { for k, r in local.roles : k => r if r.phase == "apply" }

  name   = "tfc-apply-least-privilege"
  role   = aws_iam_role.this[each.key].id
  policy = local.apply_policies[each.value.workspace]
}
