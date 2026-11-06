# tfc-oidc-baseline
#
# Deploys, FROM THE MANAGEMENT (or CloudFormation delegated-admin) ACCOUNT, a
# Terraform Cloud workload-identity baseline into member accounts — without a
# Terraform provider per account. A SERVICE_MANAGED CloudFormation StackSet
# (auto-deploying to accounts that join the targeted OUs) creates in each member:
#
#   - AWS::IAM::OIDCProvider for https://<tfc_hostname> (aud aws.workload.identity)
#   - <plan_role_name>  (default tfc-plan)  — read-only (ReadOnlyAccess plus an
#       inline deny on data-plane reads: GetObject/GetSecretValue/Decrypt/...); trusts ONLY
#       <host>:sub = organization:<org>:project:<project>:workspace:<ws>:run_phase:plan
#   - <apply_role_name> (default tfc-apply) — apply policy; trusts ONLY
#       <host>:sub = organization:<org>:project:<project>:workspace:<ws>:run_phase:apply
#       capped by a permissions boundary (default: the embedded TfcApplyBoundary
#       managed policy) so the apply identity cannot leave the org, blind the
#       detective controls, rewrite its own trust/boundary, squat or modify the
#       break-glass / OrganizationAccountAccessRole / stacksets-exec-* roles,
#       destroy or re-policy protected KMS keys, touch dp:* perimeter tags,
#       mint long-lived IAM user credentials, or create/grant to a role that
#       does not carry the same boundary (boundary propagation); every other
#       action stays allowed.
#
# Optionally (enable_member_break_glass_role) a sibling StackSet deploys the
# member-account break-glass role (see the end of this file).
#
# One template serves every account. Per-account workspace scoping is compiled
# into the template as CloudFormation Conditions keyed on AWS::AccountId, so a
# bound account gets exactly one plan/apply role pair trusting exactly its own
# workspaces, and an unbound account in a targeted OU gets only the (inert) OIDC
# provider. Policy JSON is built with jsonencode (CLAUDE.md AWS rule 3) so tests
# can jsondecode and assert on the trust conditions.
#
# The management account is NOT covered: service-managed StackSets never deploy
# to it. The management-account role the aws-organization workspace uses is a
# phase-0, human-created bootstrap role (docs/runbooks/aws-bootstrap.md).

locals {
  aud_key = "${var.tfc_hostname}:aud"
  sub_key = "${var.tfc_hostname}:sub"

  # StringLike only when workspace wildcards are explicitly allowed. The org and
  # project segments are validated wildcard-free either way.
  sub_operator = var.allow_workspace_wildcards ? "StringLike" : "StringEquals" # surfaced as an output

  # CloudFormation logical-ID suffix per binding key: security_tooling -> SecurityTooling.
  logical_suffix = {
    for k in keys(var.account_bindings) : k => join("", [for p in split("_", replace(k, "-", "_")) : title(p)])
  }

  subjects = {
    for k, b in var.account_bindings : k => {
      for phase in ["plan", "apply"] : phase => [
        for ws in b.workspaces :
        "organization:${var.tfc_organization}:project:${coalesce(b.project, var.tfc_project)}:workspace:${ws}:run_phase:${phase}"
      ]
    }
  }

  # Trust policy documents (IAM JSON objects) per binding and phase.
  trust_policies = {
    for k, b in var.account_bindings : k => {
      for phase in ["plan", "apply"] : phase => {
        Version = "2012-10-17"
        Statement = [{
          Sid       = "TfcWorkloadIdentity${title(phase)}"
          Effect    = "Allow"
          Principal = { Federated = { Ref = "TfcOidcProvider" } }
          Action    = "sts:AssumeRoleWithWebIdentity"
          # Built with for-expressions instead of a ternary so the two shapes
          # (StringEquals-only vs StringEquals + StringLike) need no type unification.
          Condition = merge(
            {
              StringEquals = merge(
                { (local.aud_key) = "aws.workload.identity" },
                { for _ in(var.allow_workspace_wildcards ? [] : [1]) : (local.sub_key) => local.subjects[k][phase] }
              )
            },
            { for _ in(var.allow_workspace_wildcards ? [1] : []) : "StringLike" => { (local.sub_key) = local.subjects[k][phase] } }
          )
        }]
      }
    }
  }

  # --- Apply-role permissions boundary ------------------------------------
  # Embedded boundary: ONE AWS::IAM::ManagedPolicy per account (unconditional, so
  # it is created even in unbound accounts of a targeted OU, where it is inert,
  # and the template does not grow per binding), unless an external boundary
  # ARN is supplied. Omitted entirely when there are no bindings.
  create_apply_boundary = var.enable_apply_permissions_boundary && var.apply_permissions_boundary_arn == null && length(var.account_bindings) > 0

  # CloudFormation Fn::Sub strings: $${...} renders a literal ${...} for CFN.
  baseline_protected_arns = [
    "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/${var.plan_role_name}",
    "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/${var.apply_role_name}",
    "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:oidc-provider/${var.tfc_hostname}",
    local.apply_boundary_arn_sub,
  ]

  # Privileged roles the apply identity must never create, modify, delete or
  # pass: the member break-glass role (squatting its NAME would inherit every
  # break-glass SCP exemption), OrganizationAccountAccessRole (rewriting its
  # trust = management-account-level access) and the StackSet execution role.
  # Defence in depth under the org deny-tamper SCP (which already never exempts
  # tfc-apply from these), so the guarantee also holds where the SCP is absent.
  privileged_role_arns_sub = [
    for n in distinct(concat([var.break_glass_role_name], var.protected_role_names)) :
    "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/${n}"
  ]

  # The embedded boundary's own ARN (CloudFormation Fn::Sub string).
  apply_boundary_arn_sub = "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:policy/${var.apply_boundary_policy_name}"

  # "Boundary must propagate": without these, the apply identity could create an
  # unbounded role, attach AdministratorAccess to it and assume it — escaping
  # every deny above. Every role tfc-apply creates (or grants permissions to)
  # must carry this same boundary, and no boundary may be removed. Consequence:
  # modules applied by tfc-apply in member accounts must set
  # permissions_boundary = arn:<partition>:iam::<account>:policy/<apply_boundary_policy_name>
  # on every aws_iam_role they create.
  # (for-expression filter, not a ternary: the two statements differ in shape.)
  apply_boundary_propagation_statements = [for s in [
    {
      Sid      = "DenyRoleWithoutApplyBoundary"
      Effect   = "Deny"
      Action   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary", "iam:AttachRolePolicy", "iam:PutRolePolicy"]
      Resource = "*"
      Condition = {
        StringNotEquals = { "iam:PermissionsBoundary" = { "Fn::Sub" = local.apply_boundary_arn_sub } }
      }
    },
    {
      Sid      = "DenyPermissionsBoundaryRemoval"
      Effect   = "Deny"
      Action   = ["iam:DeleteRolePermissionsBoundary", "iam:DeleteUserPermissionsBoundary"]
      Resource = "*"
    },
  ] : s if var.enable_apply_boundary_propagation]

  apply_boundary_document = {
    Version = "2012-10-17"
    Statement = concat([
      {
        # A boundary is an intersection: everything not denied below remains
        # grantable by the role's identity policies (apply_role_policy_arns).
        Sid      = "AllowAllNotExplicitlyDenied"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      },
      {
        Sid      = "DenyLeaveOrganization"
        Effect   = "Deny"
        Action   = ["organizations:LeaveOrganization"]
        Resource = "*"
      },
      {
        # Stop/destroy of the detective controls. Creating and updating them
        # (detectors, recorders, delivery channels) stays allowed so the
        # security/workload layers can still manage their own configuration.
        Sid    = "DenyDisablingDetectiveControls"
        Effect = "Deny"
        Action = [
          "cloudtrail:StopLogging",
          "cloudtrail:DeleteTrail",
          "guardduty:DeleteDetector",
          "guardduty:DeleteMembers",
          "guardduty:DisassociateFromAdministratorAccount",
          "guardduty:DisassociateFromMasterAccount",
          "guardduty:StopMonitoringMembers",
          "config:StopConfigurationRecorder",
          "config:DeleteConfigurationRecorder",
          "config:DeleteDeliveryChannel",
          "securityhub:Disable*",
          "securityhub:BatchDisableStandards",
          "macie2:DisableMacie",
          "inspector2:Disable",
          "access-analyzer:DeleteAnalyzer",
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyPrivilegedRoleTampering"
        Effect = "Deny"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:PutRolePermissionsBoundary",
          "iam:DeleteRolePermissionsBoundary",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PassRole",
        ]
        Resource = [for a in local.privileged_role_arns_sub : { "Fn::Sub" = a }]
      },
      {
        # Protected KMS keys (the security-stage log/forensics/tooling CMKs):
        # no destruction and no key-policy rewrite (which would let the
        # pipeline grant itself kms:Decrypt). Mirrors the SCP; CreateKey with a
        # policy is unaffected (no resource tag exists yet).
        Sid    = "DenyProtectedKeyTampering"
        Effect = "Deny"
        Action = [
          "kms:ScheduleKeyDeletion",
          "kms:DisableKey",
          "kms:DisableKeyRotation",
          "kms:DeleteImportedKeyMaterial",
          "kms:PutKeyPolicy",
        ]
        Resource  = "*"
        Condition = { StringEquals = { "aws:ResourceTag/${var.kms_protection_tag_key}" = "true" } }
      },
      {
        # Removing / rewriting the protection tag would lift both this
        # boundary statement and the SCP.
        Sid      = "DenyProtectedKeyUntag"
        Effect   = "Deny"
        Action   = ["kms:TagResource", "kms:UntagResource"]
        Resource = "*"
        Condition = {
          StringEquals               = { "aws:ResourceTag/${var.kms_protection_tag_key}" = "true" }
          "ForAnyValue:StringEquals" = { "aws:TagKeys" = var.kms_protection_tag_key }
        }
      },
      {
        # The RCP data-perimeter escape hatches (dp:exclude:*) must not be set or
        # removed by the pipeline on any tag-capable path. Mirrors the SCP.
        Sid    = "DenyDataPerimeterTagTampering"
        Effect = "Deny"
        Action = [
          "iam:CreateRole",
          "iam:TagRole",
          "iam:UntagRole",
          "s3:CreateBucket",
          "s3:PutBucketTagging",
          "s3:TagResource",
          "s3:UntagResource",
          "kms:CreateKey",
          "kms:TagResource",
          "kms:UntagResource",
          "sqs:CreateQueue",
          "sqs:TagQueue",
          "sqs:UntagQueue",
          "secretsmanager:CreateSecret",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource",
        ]
        Resource  = "*"
        Condition = { "ForAnyValue:StringLike" = { "aws:TagKeys" = "dp:*" } }
      },
      {
        # The apply identity must not rewrite its own trust, policies or
        # boundary, the sibling plan role, or the OIDC provider: those are owned
        # by this StackSet (CloudFormation's execution role is unaffected).
        Sid    = "DenyTamperingWithTfcBaseline"
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
          "iam:UpdateRoleDescription",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicy",
          "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion",
          "iam:DeleteOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:AddClientIDToOpenIDConnectProvider",
          "iam:RemoveClientIDFromOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider",
        ]
        Resource = [for a in local.baseline_protected_arns : { "Fn::Sub" = a }]
      },
      {
        # No new trust anchors from the pipeline. A role carrying this
        # boundary may still be granted AdministratorAccess; if the pipeline
        # could also register a NEW OIDC/SAML provider (an issuer it controls)
        # and point that role's trust at it, it would mint itself an
        # MFA-less, rotation-proof external door. Identity providers are
        # owned by this StackSet (TFC, and GitHub with create_github_oidc_provider)
        # and Identity Center; add-ons go through break-glass.
        Sid    = "DenyNewIdentityProviders"
        Effect = "Deny"
        Action = [
          "iam:CreateOpenIDConnectProvider",
          "iam:AddClientIDToOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:CreateSAMLProvider",
          "iam:UpdateSAMLProvider",
        ]
        Resource = "*"
      },
      {
        # No long-lived static credentials from the pipeline: identities come
        # from Identity Center and workload identity federation.
        Sid      = "DenyLongLivedIamUserCredentials"
        Effect   = "Deny"
        Action   = ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile"]
        Resource = "*"
      },
      ],
      local.apply_boundary_propagation_statements,
    )
  }

  apply_boundary_resource = local.create_apply_boundary ? {
    TfcApplyBoundary = {
      Type = "AWS::IAM::ManagedPolicy"
      Properties = {
        ManagedPolicyName = var.apply_boundary_policy_name
        Description       = "Permissions boundary for the Terraform Cloud apply role (managed by Terraform: modules/aws/iam/tfc-oidc-baseline)"
        PolicyDocument    = local.apply_boundary_document
      }
    }
  } : {}

  # The apply role's PermissionsBoundary property ({} = omitted).
  # Built with for-expressions (no ternary) so the {Ref} object and the ARN
  # string need no type unification.
  apply_boundary_property = merge(
    { for _ in(local.create_apply_boundary ? [1] : []) : "PermissionsBoundary" => { Ref = "TfcApplyBoundary" } },
    { for _ in(var.enable_apply_permissions_boundary && var.apply_permissions_boundary_arn != null ? [1] : []) : "PermissionsBoundary" => var.apply_permissions_boundary_arn },
  )

  # --- Plan-role data-plane read deny ---------------------------------------
  # ReadOnlyAccess includes data-plane reads (s3:GetObject, GetSecretValue,
  # dynamodb:Scan, ...). Speculative PR plans run as tfc-plan, so an inline deny
  # keeps the plan identity to control-plane metadata. Trade-off: planning a
  # resource whose refresh reads data (aws_s3_object, aws_secretsmanager_secret_version,
  # aws_ssm_parameter, ...) fails unless its ARN is in plan_role_data_read_exempt_arns.
  #
  # Deliberately NOT denied (Terraform plan must refresh these resources, so a
  # deny would break every plan that manages them): lambda:GetFunction /
  # GetFunctionConfiguration (returns environment variables),
  # ecs:DescribeTaskDefinition (returns container environment + secret ARNs —
  # the values stay in Secrets Manager / SSM, which ARE denied) and
  # ec2:DescribeInstanceAttribute (returns userData). Keep secrets out of Lambda
  # env vars, task-definition environment and user data; reference
  # Secrets Manager / SSM instead. Everything below is unused by refresh.
  # ssm:GetParameter* also covers GetParameters, GetParametersByPath and
  # GetParameterHistory. glue:GetConnection(s) returns connection passwords and
  # no module in this repo manages Glue.
  plan_role_data_read_deny_actions = [
    "s3:GetObject*",
    "secretsmanager:GetSecretValue",
    "secretsmanager:BatchGetSecretValue",
    "ssm:GetParameter*",
    "kms:Decrypt",
    "kms:GenerateDataKey*",
    "ec2:GetPasswordData",
    "ec2:GetConsoleOutput",
    "ec2:GetConsoleScreenshot",
    "glue:GetConnection",
    "glue:GetConnections",
    "dynamodb:GetItem",
    "dynamodb:BatchGetItem",
    "dynamodb:Query",
    "dynamodb:Scan",
    "dynamodb:PartiQLSelect",
    "dynamodb:GetRecords",
    "sqs:ReceiveMessage",
    "kinesis:GetRecords",
    "logs:GetLogEvents",
    "logs:FilterLogEvents",
    "logs:StartQuery",
    "logs:GetQueryResults",
    "logs:StartLiveTail",
    "rds-data:*",
    "redshift-data:GetStatementResult",
    "athena:GetQueryResults",
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchGetImage",
  ]

  # The plan role's Policies property ({} = omitted).
  plan_role_policies_property = {
    for _ in(var.enable_plan_role_data_read_deny ? [1] : []) : "Policies" => [{
      PolicyName = "deny-data-plane-reads"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [merge(
          {
            Sid    = "DenyDataPlaneReads"
            Effect = "Deny"
            Action = local.plan_role_data_read_deny_actions
          },
          { for _ in(length(var.plan_role_data_read_exempt_arns) > 0 ? [] : [1]) : "Resource" => "*" },
          { for _ in(length(var.plan_role_data_read_exempt_arns) > 0 ? [1] : []) : "NotResource" => var.plan_role_data_read_exempt_arns },
        )]
      }
    }]
  }

  oidc_provider = {
    TfcOidcProvider = {
      Type = "AWS::IAM::OIDCProvider"
      Properties = merge(
        {
          Url          = "https://${var.tfc_hostname}"
          ClientIdList = ["aws.workload.identity"]
        },
        { for _ in(length(var.oidc_thumbprints) > 0 ? [1] : []) : "ThumbprintList" => var.oidc_thumbprints }
      )
    }
  }

  # The account-wide GitHub Actions OIDC provider (one per account per URL).
  # Owned here, not by app-services, because the apply boundary forbids the
  # pipeline from registering identity providers (DenyNewIdentityProviders).
  github_oidc_provider = var.create_github_oidc_provider ? {
    GithubOidcProvider = {
      Type = "AWS::IAM::OIDCProvider"
      Properties = merge(
        {
          Url          = "https://token.actions.githubusercontent.com"
          ClientIdList = ["sts.amazonaws.com"]
        },
        { for _ in(length(var.oidc_thumbprints) > 0 ? [1] : []) : "ThumbprintList" => var.oidc_thumbprints }
      )
    }
  } : {}

  role_resources = merge([
    for k, b in var.account_bindings : {
      "TfcPlanRole${local.logical_suffix[k]}" = {
        Type      = "AWS::IAM::Role"
        Condition = "Is${local.logical_suffix[k]}"
        Properties = merge(
          {
            RoleName                 = var.plan_role_name
            Description              = "Terraform Cloud PLAN phase (read-only) for ${k}"
            AssumeRolePolicyDocument = local.trust_policies[k]["plan"]
            ManagedPolicyArns        = var.plan_role_policy_arns
            MaxSessionDuration       = var.max_session_duration
          },
          local.plan_role_policies_property,
        )
      }
      "TfcApplyRole${local.logical_suffix[k]}" = {
        Type      = "AWS::IAM::Role"
        Condition = "Is${local.logical_suffix[k]}"
        Properties = merge(
          {
            RoleName                 = var.apply_role_name
            Description              = "Terraform Cloud APPLY phase for ${k}"
            AssumeRolePolicyDocument = local.trust_policies[k]["apply"]
            ManagedPolicyArns        = var.apply_role_policy_arns
            MaxSessionDuration       = var.max_session_duration
          },
          local.apply_boundary_property,
        )
      }
    }
  ]...)

  conditions = {
    for k, b in var.account_bindings : "Is${local.logical_suffix[k]}" => {
      "Fn::Equals" = [{ Ref = "AWS::AccountId" }, b.account_id]
    }
  }

  template = merge(
    {
      AWSTemplateFormatVersion = "2010-09-09"
      Description              = "Terraform Cloud OIDC workload-identity baseline (managed by Terraform: modules/aws/iam/tfc-oidc-baseline)"
      Resources                = merge(local.oidc_provider, local.github_oidc_provider, local.apply_boundary_resource, local.role_resources)
      Outputs = {
        OidcProviderArn = { Value = { Ref = "TfcOidcProvider" } }
      }
    },
    # CloudFormation rejects an empty Conditions section.
    { for _ in(length(local.conditions) > 0 ? [1] : []) : "Conditions" => local.conditions }
  )

  template_body = jsonencode(local.template)
}

resource "aws_cloudformation_stack_set" "this" {
  name             = var.stack_set_name
  description      = "Terraform Cloud OIDC provider + per-workspace plan/apply roles for member accounts."
  permission_model = "SERVICE_MANAGED"
  call_as          = var.call_as
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  template_body    = local.template_body
  tags             = var.tags

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
    # Known provider behaviour: AWS populates administration_role_arn on
    # SERVICE_MANAGED stack sets, which otherwise shows as perpetual drift.
    ignore_changes = [administration_role_arn]

    precondition {
      # Inline template_body limit is 51,200 bytes; beyond that a template_url
      # (S3) would be required.
      condition     = length(local.template_body) <= 51200
      error_message = "The generated StackSet template exceeds CloudFormation's 51,200-byte inline limit — reduce account_bindings or split the baseline."
    }
  }
}

# One stack instance per targeted OU, keyed by stable OU name so adding an OU
# never replaces (and thereby deletes) the instances for the existing OUs.
resource "aws_cloudformation_stack_set_instance" "this" {
  for_each = var.target_ou_ids

  stack_set_name            = aws_cloudformation_stack_set.this.name
  call_as                   = var.call_as
  stack_set_instance_region = var.stack_set_instance_region
  retain_stack              = false

  deployment_targets {
    organizational_unit_ids = [each.value]
  }

  operation_preferences {
    failure_tolerance_count = 0
    max_concurrent_count    = 10
  }
}

# ---------------------------------------------------------------------------
# Member-account break-glass role (sibling SERVICE_MANAGED StackSet)
#
# The org deny-tamper SCP exempts break-glass by role NAME
# (arn:aws:iam::*:role/<name>). If no role with that name exists in a member
# account, whoever creates one there first inherits every break-glass
# exemption. This StackSet occupies the name in every account of the targeted
# OUs (default: the org root via the organization stage) with a role that
# trusts ONLY the management-account break-glass principal(s), MFA required.
# The SCP (DenyStackSetRoleTampering) and the tfc-apply boundary
# (DenyPrivilegedRoleTampering) stop the pipeline creating, modifying or
# deleting it; only break-glass and the StackSet execution role may.
# ---------------------------------------------------------------------------

locals {
  break_glass_name_parts = split("/", var.break_glass_role_name)
  break_glass_role_short = element(local.break_glass_name_parts, length(local.break_glass_name_parts) - 1)
  break_glass_role_path  = length(local.break_glass_name_parts) > 1 ? "/${join("/", slice(local.break_glass_name_parts, 0, length(local.break_glass_name_parts) - 1))}/" : "/"

  member_break_glass_trust = {
    Version = "2012-10-17"
    Statement = [merge(
      {
        Sid       = "BreakGlassFromManagementAccount"
        Effect    = "Allow"
        Principal = { AWS = var.member_break_glass_trusted_principal_arns }
        Action    = "sts:AssumeRole"
      },
      { for _ in(var.member_break_glass_require_mfa ? [1] : []) : "Condition" => {
        Bool            = { "aws:MultiFactorAuthPresent" = "true" }
        NumericLessThan = { "aws:MultiFactorAuthAge" = tostring(var.member_break_glass_mfa_max_age) }
      } },
    )]
  }

  member_break_glass_template = {
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "Member-account break-glass role (managed by Terraform: modules/aws/iam/tfc-oidc-baseline)"
    Resources = {
      MemberBreakGlassRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName                 = local.break_glass_role_short
          Path                     = local.break_glass_role_path
          Description              = "Emergency break-glass access; assumable only from the management-account break-glass principal with MFA"
          AssumeRolePolicyDocument = local.member_break_glass_trust
          ManagedPolicyArns        = var.member_break_glass_policy_arns
          MaxSessionDuration       = 3600
        }
      }
    }
    Outputs = {
      BreakGlassRoleArn = { Value = { "Fn::GetAtt" = ["MemberBreakGlassRole", "Arn"] } }
    }
  }

  member_break_glass_template_body = jsonencode(local.member_break_glass_template)
}

resource "aws_cloudformation_stack_set" "break_glass" {
  count = var.enable_member_break_glass_role ? 1 : 0

  name             = var.member_break_glass_stack_set_name
  description      = "Member-account break-glass role (occupies the SCP-exempt break-glass name; trusts the management-account break-glass principal with MFA)."
  permission_model = "SERVICE_MANAGED"
  call_as          = var.call_as
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  template_body    = local.member_break_glass_template_body
  tags             = var.tags

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

    precondition {
      condition     = length(var.member_break_glass_trusted_principal_arns) > 0
      error_message = "enable_member_break_glass_role = true requires at least one member_break_glass_trusted_principal_arns entry."
    }
  }
}

resource "aws_cloudformation_stack_set_instance" "break_glass" {
  for_each = var.enable_member_break_glass_role ? var.member_break_glass_target_ou_ids : {}

  stack_set_name            = aws_cloudformation_stack_set.break_glass[0].name
  call_as                   = var.call_as
  stack_set_instance_region = var.stack_set_instance_region
  retain_stack              = false

  deployment_targets {
    organizational_unit_ids = [each.value]
  }

  operation_preferences {
    failure_tolerance_count = 0
    max_concurrent_count    = 10
  }
}
