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

  # Delegated-admin account resources; fails closed with no account given.
  delegated_admin_resources = length(var.delegated_admin_account_ids) == 0 ? ["arn:${local.partition}:organizations::${local.account_id}:account/o-*/none"] : [
    for id in var.delegated_admin_account_ids : "arn:${local.partition}:organizations::${local.account_id}:account/o-*/${id}"
  ]

  trail_log_group_arns = [
    "arn:${local.partition}:logs:*:${local.account_id}:log-group:/aws/cloudtrail/${var.security_trail_name}",
    "arn:${local.partition}:logs:*:${local.account_id}:log-group:/aws/cloudtrail/${var.security_trail_name}:*",
  ]

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

          "guardduty:EnableOrganizationAdminAccount",
          "guardduty:ListOrganizationAdminAccounts",
          "securityhub:EnableOrganizationAdminAccount",
          "securityhub:ListOrganizationAdminAccounts",
          "macie2:EnableOrganizationAdminAccount",
          "macie2:ListOrganizationAdminAccounts",
          "inspector2:EnableDelegatedAdminAccount",
          "inspector2:ListDelegatedAdminAccounts",
          "detective:EnableOrganizationAdminAccount",
          "detective:ListOrganizationAdminAccount",
          "fms:AssociateAdminAccount",
          "fms:GetAdminAccount",
          "iam:CreateServiceLinkedRole",
        ]
        Resource = "*"
      },
      {
        # Delegated administration ONLY for the security services. Registering
        # an account as delegated admin for e.g. member.org.stacksets or sso
        # would hand it org-wide role deployment / identity control.
        Sid    = "SecurityServicesDelegationOnly"
        Effect = "Allow"
        # Enable only: turning org-wide detection OFF is SecurityServiceTeardown.
        Action    = ["organizations:EnableAWSServiceAccess"]
        Resource  = "*"
        Condition = { StringEquals = { "organizations:ServicePrincipal" = var.security_service_principals } }
      },
      {
        # Registration is pinned to the TARGET account too (the account ARN is
        # the resource): the pipeline can make only the security-tooling
        # account a delegated admin, never an arbitrary member.
        Sid    = "DelegateOnlyToSecurityAccounts"
        Effect = "Allow"
        Action = ["organizations:RegisterDelegatedAdministrator"]
        # Fails closed: with no security account given, the statement grants
        # nothing (a resource no account ARN can match) rather than every account.
        Resource  = local.delegated_admin_resources
        Condition = { StringEquals = { "organizations:ServicePrincipal" = var.security_service_principals } }
      },
      {
        # The organization trail's own wiring only. No IAM writes at all (the
        # trail delivery role is created by aws-organization and only PASSED
        # to CloudTrail here); destructive trail and key actions are denied
        # below (break-glass only). Everything else in the management account
        # (other log groups, topics, keys) is out of reach.
        Sid    = "TrailWiringCreate"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:Describe*", "logs:List*",
          "sns:CreateTopic", "sns:List*",
          "cloudwatch:Describe*", "cloudwatch:ListTagsForResource",
          "kms:List*", "kms:Describe*",
        ]
        Resource = "*"
      },
      {
        # The CIS alarms are named <trail>-<check>: no other alarm in the
        # management account can be changed or deleted.
        Sid    = "TrailAlarmsOnly"
        Effect = "Allow"
        # No DeleteAlarms: deleting (or silencing) a CIS alarm is denied below.
        Action   = ["cloudwatch:PutMetricAlarm", "cloudwatch:TagResource", "cloudwatch:UntagResource"]
        Resource = ["arn:${local.partition}:cloudwatch:*:${local.account_id}:alarm:${var.security_trail_name}-*"]
      },
      {
        Sid      = "TrailLogGroupOnly"
        Effect   = "Allow"
        Action   = ["logs:*"]
        Resource = local.trail_log_group_arns
      },
      {
        Sid      = "TrailTopicsOnly"
        Effect   = "Allow"
        Action   = ["sns:*"]
        Resource = ["arn:${local.partition}:sns:*:${local.account_id}:${var.security_trail_name}-*"]
      },
      {
        # Keys may be created (and tagged at creation) only with the owner tag.
        # Deliberately NO aws:TagKeys allow-list: the aws-security provider's
        # default_tags (ManagedBy, LandingZone, Environment, ...) are applied to
        # every key it creates, so an allow-list would deny CreateKey itself.
        # Tags grant NOTHING afterwards: day-2 management of the key is by its
        # own key policy (PipelineKeyManagement in cloudtrail-org), so a tag
        # cannot be planted on someone else's key to gain kms:* on it.
        Sid       = "CreateOwnedKeysOnly"
        Effect    = "Allow"
        Action    = ["kms:CreateKey", "kms:TagResource"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestTag/${var.security_owner_tag.key}" = var.security_owner_tag.value } }
      },
      {
        Sid    = "TrailKeyAliasesOnly"
        Effect = "Allow"
        Action = ["kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias"]
        Resource = [
          "arn:${local.partition}:kms:*:${local.account_id}:alias/${var.security_trail_name}-*",
        ]
      },
      {
        # Trail writes only on THE organization trail: no second trail, no
        # repointing another trail. Reads come from ReadOnlyAccess.
        Sid      = "OrganizationTrailOnly"
        Effect   = "Allow"
        Action   = ["cloudtrail:*"]
        Resource = ["arn:${local.partition}:cloudtrail:*:${local.account_id}:trail/${var.security_trail_name}"]
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
        # Repointing the trail (UpdateTrail: bucket, KMS key, org / multi-region
        # flags) or rewriting a key's policy / grants / rotation is as good as
        # stopping it. The key policy is set at CreateKey and the trail's
        # settings at CreateTrail, so routine applies never need these.
        # Untagging the trail or rewriting its resource policy is the same.
        # PutEventSelectors stays allowed (aws_cloudtrail calls it on create);
        # selector changes are DETECTED by the aws-organization guard-alerts
        # EventBridge rule (the CIS 4.5 alarm does not match selector calls).
        Sid    = "DenyTrailAndKeyDestruction"
        Effect = "Deny"
        Action = [
          "cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:UpdateTrail",
          "cloudtrail:RemoveTags", "cloudtrail:PutResourcePolicy", "cloudtrail:DeleteResourcePolicy",
          "kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:DeleteImportedKeyMaterial",
          "kms:PutKeyPolicy", "kms:CreateGrant", "kms:DisableKeyRotation",
        ]
        Resource = "*"
      },
      {
        # Deleting or silencing a CIS alarm blinds the trail's alerting.
        Sid      = "DenyTrailAndKeyDestructionAlarms"
        Effect   = "Deny"
        Action   = ["cloudwatch:DeleteAlarms", "cloudwatch:DisableAlarmActions"]
        Resource = ["arn:${local.partition}:cloudwatch:*:${local.account_id}:alarm:${var.security_trail_name}-*"]
      },
      {
        # The trail log group, its metric filters (the CIS alarms' inputs) and
        # its retention survive the pipeline. PutRetentionPolicy stays allowed.
        Sid      = "DenyTrailAndKeyDestructionLogs"
        Effect   = "Deny"
        Action   = ["logs:DeleteLogGroup", "logs:DeleteRetentionPolicy", "logs:DeleteSubscriptionFilter", "logs:DeleteMetricFilter"]
        Resource = local.trail_log_group_arns
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

  # Teardown gate (enable_security_service_teardown): switching org-wide
  # detection OFF. A separate inline policy on the aws-security apply role, so
  # it exists only while the gate is on and is removed when it is turned off.
  security_teardown_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Teardown gate (enable_security_service_teardown): switching org-wide
        # detection OFF. Never on for routine applies.
        Sid    = "SecurityServiceTeardown"
        Effect = "Allow"
        Action = [
          "guardduty:DisableOrganizationAdminAccount",
          "securityhub:DisableOrganizationAdminAccount",
          "macie2:DisableOrganizationAdminAccount",
          "inspector2:DisableDelegatedAdminAccount",
          "detective:DisableOrganizationAdminAccount",
          "fms:DisassociateAdminAccount",
        ]
        Resource = "*"
      },
      {
        Sid       = "SecurityServiceTeardownTrustedAccess"
        Effect    = "Allow"
        Action    = ["organizations:DisableAWSServiceAccess"]
        Resource  = "*"
        Condition = { StringEquals = { "organizations:ServicePrincipal" = var.security_service_principals } }
      },
      {
        Sid       = "SecurityServiceTeardownDelegation"
        Effect    = "Allow"
        Action    = ["organizations:DeregisterDelegatedAdministrator"]
        Resource  = local.delegated_admin_resources
        Condition = { StringEquals = { "organizations:ServicePrincipal" = var.security_service_principals } }
      },
    ]
  })

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
      "dynamodb:Query", "dynamodb:Scan", "dynamodb:BatchGetItem", "dynamodb:PartiQLSelect",
      "ssm:GetParameterHistory", "sqs:ReceiveMessage",
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

# Only while the teardown gate is on, and only for a built-in aws-security
# policy (a custom apply_policy_json owns its own teardown permissions).
resource "aws_iam_role_policy" "security_teardown" {
  for_each = {
    for k, r in local.roles : k => r
    if r.phase == "apply" && r.workspace == "aws-security" && var.enable_security_service_teardown && var.workspaces[r.workspace].apply_policy_json == null
  }

  name   = "tfc-apply-security-teardown"
  role   = aws_iam_role.this[each.key].id
  policy = local.security_teardown_policy
}
