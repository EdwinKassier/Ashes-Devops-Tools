# Organization Structure
#
# Standing org/billing admin goes to GROUPS only. Individual user principals
# (admin_email, break_glass_user) are granted only with the explicit
# allow_user_principals_for_break_glass escape hatch; prefer a break-glass group
# plus the just-in-time PAM entitlement (pam.tf) for human elevation.
locals {
  admin_user_members = var.allow_user_principals_for_break_glass ? distinct(concat(
    ["user:${var.admin_email}"],
    var.break_glass_user != null ? ["user:${var.break_glass_user}"] : [],
  )) : []

  org_admin_members = distinct(concat(
    [for group in var.organization_admin_groups : "group:${group}"],
    local.admin_user_members,
  ))

  billing_admin_members = distinct(concat(
    [for group in var.billing_admin_groups : "group:${group}"],
    var.allow_user_principals_for_break_glass ? ["user:${var.admin_email}"] : [],
  ))

  production_environment_keys = sort([for k, e in var.environments : k if e.is_production])
}

module "organization" {
  source = "../../iam/organization"

  domain     = var.domain
  project_id = var.admin_project_id

  org_admin_members     = local.org_admin_members
  billing_admin_members = local.billing_admin_members

  # Organizational Units (excluding projects, they are created later)
  organizational_units = var.environments
}

# LEGACY: grant the phase-0 bootstrap SA (terraform-admin) rights on every folder.
# Superseded by the per-stage plan/apply service accounts: gcp-projects
# creates projects as projects-apply (org-level projectCreator/billing) and grants
# the network-hub and wl-<env> SAs their folder roles. Off by default so the
# bootstrap identity holds no standing folder-admin rights; enable only while
# migrating an existing deployment that still runs every stage as terraform-admin.
resource "google_folder_iam_member" "terraform_admin_folder_roles" {
  for_each = !var.enable_legacy_admin_folder_roles ? {} : {
    for pair in flatten([
      for folder_key, folder in module.organization.folders : [
        for role in [
          "roles/resourcemanager.folderAdmin",
          "roles/resourcemanager.projectCreator",
          "roles/billing.projectManager",
          "roles/compute.networkAdmin"
          ] : {
          key    = "${folder_key}-${role}"
          folder = folder.id
          role   = role
        }
      ]
    ]) : pair.key => pair
  }

  folder = each.value.folder
  role   = each.value.role
  member = "serviceAccount:${var.terraform_admin_email}"
}


# Centralized Audit Logs
locals {
  # Audit G4 / C3: separation of duties. When logging_project_id is set, the org
  # audit bucket AND its CMEK keys live in that dedicated logging project (which
  # the Terraform admin/automation SA must NOT own — see variable docs), instead
  # of the admin/bootstrap project. Default null = admin project (unchanged).
  separate_logging_project = var.logging_project_id != null
  audit_project_id         = coalesce(var.logging_project_id, var.admin_project_id)
  audit_project_number     = local.separate_logging_project ? coalesce(var.logging_project_number, "0") : var.admin_project_number

  # CMEK keys for the audit store, granted to the GCS / BigQuery service agents
  # of the project that actually holds the bucket and dataset.
  audit_cmek_keys = {
    "audit-logs" = {
      encrypter_decrypters = [
        "serviceAccount:service-${local.audit_project_number}@gs-project-accounts.iam.gserviceaccount.com",
      ]
    }
    "audit-analytics" = {
      encrypter_decrypters = [
        "serviceAccount:bq-${local.audit_project_number}@bigquery-encryption.iam.gserviceaccount.com",
      ]
    }
  }

  audit_key_names = local.separate_logging_project ? module.audit_cmek[0].key_names : module.cmek.key_names
}

module "cmek" {
  source = "../../governance/kms"

  project_id   = var.admin_project_id
  keyring_name = "${var.project_prefix}-org-cmek"
  location     = var.default_region

  # The audit keys stay here only when there is no dedicated logging project.
  # Decide logging_project_id BEFORE the first apply: KMS keys cannot be deleted,
  # so moving them later leaves orphaned (prevent_destroy) keys behind.
  keys = merge(
    local.separate_logging_project ? {} : local.audit_cmek_keys,
    {
      "billing-alerts" = {
        encrypter_decrypters = [
          "serviceAccount:service-${var.admin_project_number}@gcp-sa-pubsub.iam.gserviceaccount.com",
        ]
      }
      "scc-notifications" = {
        encrypter_decrypters = [
          "serviceAccount:service-${var.admin_project_number}@gcp-sa-pubsub.iam.gserviceaccount.com",
        ]
      }
      "billing-export" = {
        encrypter_decrypters = [
          "serviceAccount:bq-${var.admin_project_number}@bigquery-encryption.iam.gserviceaccount.com",
        ]
      }
    }
  )
}

# Audit-store CMEK in the dedicated logging project (only when logging_project_id is set).
module "audit_cmek" {
  source = "../../governance/kms"
  count  = local.separate_logging_project ? 1 : 0

  project_id   = local.audit_project_id
  keyring_name = "${var.project_prefix}-audit-cmek"
  location     = var.default_region
  keys         = local.audit_cmek_keys
}

module "audit_logs" {
  source = "../../governance/cloud-audit-logs"

  # Audit G4: the org audit sink/bucket go to the dedicated logging project when
  # set (default null = admin project). The bucket's CMEK key comes from the same
  # project (module.audit_cmek) so no cross-project KMS grant is needed.
  project_id                 = local.audit_project_id
  bucket_location            = var.default_region
  log_retention_days         = var.audit_log_retention_days
  enable_bucket_lock         = var.enable_audit_bucket_lock
  soft_delete_retention_days = var.audit_soft_delete_retention_days
  org_id                     = var.org_id
  kms_key_name               = local.audit_key_names["audit-logs"]

  # Log Analytics: org audit logs in an analytics-enabled log bucket with a
  # linked BigQuery dataset (Google's current recommendation).
  enable_log_analytics         = var.enable_log_analytics
  log_analytics_retention_days = var.log_analytics_retention_days

  # Enable BigQuery Analytics for improved security investigation
  enable_bigquery_analytics = true
  bigquery_location         = var.default_region
  bigquery_kms_key_name     = local.audit_key_names["audit-analytics"]
}

# Control-plane alerting (audit Security High: "No control-plane alerting").
# Log-match alerts on org IAM, org policy, VPC-SC, sink/exclusion, custom-role,
# deny-policy and KMS-destroy changes, plus any break-glass use. Lives in the
# audit/logging project; an aggregated org sink routes org- and folder-level
# Admin Activity logs there so the watches can see them. With no notification
# channels the alerts still fire (visible in Cloud Monitoring) but notify no-one
# — the check block below warns about that.
module "control_plane_alerting" {
  source = "../../monitoring/control-plane"

  enable                         = var.enable_control_plane_alerting
  project_id                     = local.audit_project_id
  org_id                         = var.org_id
  notification_email_addresses   = var.alert_notification_emails
  extra_notification_channel_ids = var.alert_notification_channels
  break_glass_principal_emails = distinct(concat(
    var.break_glass_user != null ? [var.break_glass_user] : [],
    var.break_glass_principal_emails,
  ))

  # CIS GCP 2.4-2.11 log-based metrics + alerts, fed org-wide by the aggregated
  # org sink (every project's Admin Activity logs).
  enable_cis_log_metrics = var.enable_cis_log_metrics
}

# Production needs the containment deny policy: without it the automation
# identity can retarget the audit sink, untag and delete the audit store or empty
# a perimeter. Warn (never fail) so a non-prod bootstrap still applies.
check "production_requires_admin_containment" {
  assert {
    condition     = length(local.production_environment_keys) == 0 || var.enable_admin_containment || var.production_containment_waived
    error_message = "Production environments (${join(", ", local.production_environment_keys)}) exist but enable_admin_containment = false: the audit store and VPC-SC perimeters are not protected from the automation identity. Enable it with a real break-glass group (examples/presets/prod-gcp-organization.tfvars). The WORM lock (enable_audit_bucket_lock) stays a separate, irreversible opt-in."
  }
}

check "control_plane_alerts_have_a_destination" {
  assert {
    condition     = !var.enable_control_plane_alerting || length(var.alert_notification_emails) + length(var.alert_notification_channels) > 0
    error_message = "Control-plane alerting is enabled but neither alert_notification_emails nor alert_notification_channels is set: guardrail-change alerts will fire without notifying anyone."
  }
}

# Security Command Center Notifications
module "scc_notifications" {
  source = "../../governance/scc"

  org_id            = var.org_id
  project_id        = var.admin_project_id
  pubsub_topic_name = "scc-findings"
  config_id         = "scc-notify-all-active"
  filter            = "state=\"ACTIVE\""
  kms_key_name      = module.cmek.key_names["scc-notifications"]
}

# Resource Manager Tags (Metadata & Governance)
module "tags" {
  source = "../../governance/tags"

  org_id = var.org_id

  tags = merge({
    "environment" = {
      values      = sort(keys(var.environments))
      description = "Deployment environment tier (e.g. dev, staging, prod)"
    }
    "business-unit" = {
      values      = ["engineering", "product", "sales"]
      description = "Owning business unit for cost allocation and access scoping"
    }
    "data-classification" = {
      values      = ["public", "internal", "confidential", "restricted"]
      description = "Data sensitivity level per the organization data classification policy"
    }
    }, var.enable_admin_containment ? {
    # Marks the audit store (buckets + CMEK keyring) for the tag-conditioned
    # containment deny rule. IAM deny conditions can only match resource tags.
    "containment" = {
      values      = ["protected"]
      description = "Resources protected by the admin-containment IAM deny policy. Do not bind elsewhere without review."
    }
  } : {})
}

# Organization Policies (Governance)
locals {
  # Opt-in CMEK-required org policy (gcp.restrictNonCmekServices). Default
  # off (empty list), so a default apply is unchanged. Enable with
  # var.enable_cmek_org_policy; the hardening preset turns it on. Admins choose
  # which services require CMEK via var.cmek_required_services.
  cmek_list_policy = var.enable_cmek_org_policy ? [
    {
      constraint     = "gcp.restrictNonCmekServices"
      allow_all      = false
      deny_all       = false
      allowed_values = []
      denied_values  = var.cmek_required_services
    }
  ] : []

  # Opt-in containment of the automation (Terraform-admin) identity. A
  # CI/WIF compromise of that SA could otherwise erase or blind the audit trail
  # and remove the VPC-SC data perimeter. Two deny rules, both exempting only
  # containment_exempt_principals (break-glass):
  #
  #  1. ORG-WIDE (unconditional): mutation of logging sinks/exclusions/log
  #     buckets and of VPC-SC perimeters/access policies. NOTE: this includes
  #     sinks.update and servicePerimeters.update, which Terraform uses
  #     legitimately — once enabled, ANY change to a sink, exclusion or perimeter
  #     anywhere in the org (including workload perimeters/flow-log sinks) must be
  #     applied by a break-glass/exempt principal. That is the point: the
  #     automation identity can no longer retarget or blank the audit sink or
  #     empty a perimeter. Sink/perimeter CREATION stays allowed.
  #  2. TAG-SCOPED to the audit store (tag containment/protected, bound to the
  #     audit + access-log buckets and the audit CMEK keyring in containment.tf):
  #     bucket delete/IAM change, bucket tag-binding delete (so the tag that
  #     scopes this rule cannot be stripped first), object delete, key-version
  #     destroy and disable (cryptoKeyVersions.update), key IAM change. IAM deny
  #     conditions can ONLY match resource tags, so the tag is how the deny is
  #     scoped to the audit bucket rather than every bucket.
  #
  # Every permission below was checked against the IAM deny supported-permissions
  # list (docs.cloud.google.com/iam/docs/deny-permissions-support, re-verified
  # 2026-11). Permissions requested but OMITTED because they are not on it:
  #  - iam.denypolicies.update / iam.denypolicies.delete — a deny policy cannot
  #    protect itself; the control-plane watch "deny_policy_change" alerts instead.
  #  - accesscontextmanager.accessPolicies.delete — the supported name is
  #    accesscontextmanager.googleapis.com/policies.delete (used below; the
  #    previous accessPolicies.delete string was invalid).
  #  - resourcemanager.tagValueBindings.delete / tagValues.delete / tagKeys.delete
  #    and cloudkms keyRings.deleteTagBinding — not deny-supported. The bucket
  #    tag binding IS protected (storage buckets.deleteTagBinding); the keyring
  #    binding and the tag key/value are covered by the control-plane watch
  #    "tag_binding_change" (a tag value with live bindings cannot be deleted).
  # orgpolicy.policy.set is deliberately NOT denied: Terraform sets org policies
  # every time the baseline changes; the org_policy_change watch covers it.
  # Default off: enable only after validating on a non-prod org.
  containment_deny_policy = var.enable_admin_containment ? [
    {
      name         = "contain-admin-identity"
      display_name = "Contain automation identity"
      rules = [
        {
          description       = "Org-wide: deny mutation of logging sinks/exclusions/log buckets and VPC-SC perimeters to all but break-glass."
          denied_principals = ["principalSet://goog/public:all"]
          denied_permissions = concat([
            "logging.googleapis.com/sinks.update",
            "logging.googleapis.com/sinks.delete",
            "logging.googleapis.com/exclusions.create",
            "logging.googleapis.com/exclusions.update",
            "logging.googleapis.com/exclusions.delete",
            "logging.googleapis.com/buckets.delete",
            "accesscontextmanager.googleapis.com/servicePerimeters.update",
            "accesscontextmanager.googleapis.com/servicePerimeters.delete",
            "accesscontextmanager.googleapis.com/servicePerimeters.replaceAll",
            "accesscontextmanager.googleapis.com/servicePerimeters.commit",
            "accesscontextmanager.googleapis.com/policies.delete",
            # N3: access levels gate perimeter ingress, and access-policy IAM /
            # scopes decide who may edit perimeters. Creation stays allowed (a
            # new level is inert until a perimeter, itself protected, uses it).
            "accesscontextmanager.googleapis.com/accessLevels.update",
            "accesscontextmanager.googleapis.com/accessLevels.delete",
            "accesscontextmanager.googleapis.com/accessLevels.replaceAll",
            "accesscontextmanager.googleapis.com/authorizedOrgsDescs.create",
            "accesscontextmanager.googleapis.com/authorizedOrgsDescs.update",
            "accesscontextmanager.googleapis.com/authorizedOrgsDescs.delete",
            "accesscontextmanager.googleapis.com/policies.update",
            "accesscontextmanager.googleapis.com/policies.setIamPolicy",
            ], var.enable_principal_access_boundary ? [
            # The automation boundary must not be loosened or unbound by the
            # identities it bounds (bind/create stay allowed).
            "iam.googleapis.com/principalaccessboundarypolicies.update",
            "iam.googleapis.com/principalaccessboundarypolicies.delete",
            "iam.googleapis.com/principalaccessboundarypolicies.unbind",
          ] : [])
          exception_principals = var.containment_exempt_principals
          denial_condition     = null
        },
        {
          description       = "Audit store (tag containment/protected): deny bucket delete/update/IAM change/untag, object delete, key-version destroy/disable, key and keyring IAM change and Log Analytics bucket update/untag to all but break-glass."
          denied_principals = ["principalSet://goog/public:all"]
          denied_permissions = [
            "storage.googleapis.com/buckets.delete",
            "storage.googleapis.com/buckets.setIamPolicy",
            "storage.googleapis.com/buckets.deleteTagBinding",
            # N3: buckets.update covers retention policy, lifecycle, versioning,
            # soft delete, CMEK and logging config of the audit buckets.
            "storage.googleapis.com/buckets.update",
            "storage.googleapis.com/objects.delete",
            "cloudkms.googleapis.com/cryptoKeyVersions.destroy",
            "cloudkms.googleapis.com/cryptoKeyVersions.update",
            "cloudkms.googleapis.com/cryptoKeys.setIamPolicy",
            "cloudkms.googleapis.com/keyRings.setIamPolicy",
            # The audit Log Analytics bucket (tagged in containment.tf):
            # retention / lock / analytics changes and untagging.
            "logging.googleapis.com/buckets.update",
            "logging.googleapis.com/buckets.deleteTagBinding",
          ]
          exception_principals = var.containment_exempt_principals
          denial_condition = {
            title       = "audit-store-only"
            description = "Applies only to resources carrying the containment/protected tag (the audit buckets, the audit Log Analytics bucket and the audit CMEK keyring)."
            expression  = "resource.matchTagId('${try(module.tags.tag_keys["containment"], "")}', '${try(module.tags.tag_values["containment-protected"], "")}')"
          }
        },
      ]
    }
  ] : []
}

module "org_policies" {
  source = "../../governance/org-policy"

  parent = "organizations/${module.organization.organization_id}"

  # Managed constraints (constraints/*.managed.*) replace their legacy
  # equivalents where Google offers a like-for-like successor.
  # iam.allowedPolicyMemberDomains stays legacy: its successor
  # iam.managed.allowedPolicyMembers blocks the automatic Owner / Folder Admin
  # grants made at project and folder creation and Google-owned principals
  # outside the org (see docs/known-gaps.md).
  prefer_managed_constraints = var.prefer_managed_constraints

  list_policies    = local.effective_list_policies
  boolean_policies = local.effective_boolean_policies

  # Opt-in custom organization-policy constraints (CEL-defined, resource-shape
  # guardrails the fixed boolean/list constraints can't express). Default [] =
  # none. See docs/known-gaps.md (G6).
  custom_constraints = var.custom_org_constraints
}

locals {
  # A bare region ("europe-west2") in gcp.resourceLocations matches the region
  # only, not its zones, so zonal resources (VMs, GKE nodes, Cloud SQL zones)
  # would be denied. Bare regions become the in:<region>-locations value group;
  # anything already a value group or a zone/multi-region is passed through.
  resource_location_values = [
    for r in var.allowed_regions : can(regex("^[a-z]+-[a-z]+[0-9]+$", r)) ? "in:${r}-locations" : r
  ]

  # Workload identity federation is limited to the issuers this estate trusts
  # (TFC dynamic credentials, GitHub Actions for app deploys). Without it any
  # project owner can register a provider for an issuer they control and bind
  # it to a service account: a durable external door that domain-restricted
  # sharing does not see (principalSet:// members are not domain-checked).
  default_list_policies = concat([
    {
      constraint     = "gcp.resourceLocations"
      allowed_values = local.resource_location_values
      denied_values  = null
      allow_all      = null
      deny_all       = null
    },
    {
      constraint     = "iam.allowedPolicyMemberDomains"
      allowed_values = [var.customer_id]
      denied_values  = null
      allow_all      = null
      deny_all       = null
    },
    # Network Security: Restrict VPC peering to within the organization only
    {
      constraint     = "compute.restrictVpcPeering"
      allowed_values = ["under:organizations/${module.organization.organization_id}"]
      denied_values  = null
      allow_all      = null
      deny_all       = null
    },
    # CIS 4.9: Deny all external IPs for VM instances (list constraint — deny_all = true
    # means no VM may have an external IP assigned unless an org policy override exists).
    # compute.vmExternalIpAccess is a LIST constraint, not a boolean constraint.
    # Using it in boolean_policies would silently send an invalid policy spec to the API.
    {
      constraint     = "compute.vmExternalIpAccess"
      allowed_values = []
      denied_values  = null
      allow_all      = null
      deny_all       = true
    },
    {
      constraint     = "iam.workloadIdentityPoolProviders"
      allowed_values = var.allowed_workload_identity_issuers
      denied_values  = null
      allow_all      = null
      deny_all       = length(var.allowed_workload_identity_issuers) == 0 ? true : null
    },
    # No AWS-account federation unless listed.
    {
      constraint     = "iam.workloadIdentityPoolAwsAccounts"
      allowed_values = var.allowed_workload_identity_aws_accounts
      denied_values  = null
      allow_all      = null
      deny_all       = length(var.allowed_workload_identity_aws_accounts) == 0 ? true : null
    },
    # Only internal protocol forwarding: no external forwarding rules that
    # bypass the load-balancer + Cloud Armor edge.
    {
      constraint     = "compute.restrictProtocolForwardingCreationForTypes"
      allowed_values = ["INTERNAL"]
      denied_values  = null
      allow_all      = null
      deny_all       = null
    }
    ], local.cmek_list_policy,
    # Cloud Run ingress: no service may accept traffic from the internet directly
    # (ingress "all"). Public apps go through the external ALB + Cloud Armor
    # (internal-and-cloud-load-balancing). Closes the invoker_iam_disabled +
    # INGRESS_TRAFFIC_ALL bypass of domain-restricted sharing.
    var.restrict_cloud_run_ingress ? [{
      constraint     = "run.allowedIngress"
      allowed_values = ["internal", "internal-and-cloud-load-balancing"]
      denied_values  = null
      allow_all      = null
      deny_all       = null
  }] : [])

  default_boolean_policies = concat([
    {
      constraint = "compute.skipDefaultNetworkCreation"
      enforce    = true
    },
    {
      constraint = "compute.requireShieldedVm"
      enforce    = true
    },
    {
      constraint = "sql.restrictPublicIp"
      enforce    = true
    },
    {
      constraint = "iam.disableServiceAccountKeyCreation"
      enforce    = true
    },
    {
      constraint = "compute.disableSerialPortAccess"
      enforce    = true
    },
    {
      constraint = "storage.uniformBucketLevelAccess"
      enforce    = true
    },
    # Block public access to Cloud Storage org-wide. Uniform
    # bucket-level access alone does NOT prevent allUsers/allAuthenticatedUsers
    # grants; publicAccessPrevention is the constraint that does.
    {
      constraint = "storage.publicAccessPrevention"
      enforce    = true
    },
    # CIS 1.4: Disable automatic IAM grants for default service accounts
    {
      constraint = "iam.automaticIamGrantsForDefaultServiceAccounts"
      enforce    = true
    },
    # Security: Disable service account key upload
    {
      constraint = "iam.disableServiceAccountKeyUpload"
      enforce    = true
    },
    # Security: Require VPC Connector for Cloud Functions
    {
      constraint = "cloudfunctions.requireVPCConnector"
      enforce    = true
    },
    # Security: Require Private Google Access for secure API access
    {
      constraint = "compute.requirePrivateGoogleAccess"
      enforce    = true
    },
    # No external IPv6 on VPC subnets (the IPv6 twin of vmExternalIpAccess).
    {
      constraint = "compute.disableVpcExternalIpv6"
      enforce    = true
    },
    # Zonal DNS for new projects: a zone outage cannot take out instance DNS.
    {
      constraint = "compute.setNewProjectDefaultToZonalDNSOnly"
      enforce    = true
    }
    ], var.enforce_os_login ? [
    # CIS GCP 4.4: OS Login org-wide. Folders in os_login_exempt_environment_keys
    # get a folder-level override (module.os_login_exemptions).
    {
      constraint = "compute.requireOsLogin"
      enforce    = true
    }
  ] : [])

  # org_policy_overrides: change or drop a baseline constraint without forking
  # the stage. A boolean override sets enforce; a list override replaces the
  # value fields; disabled = true removes the constraint from the baseline.
  # Constraints not in the baseline are added (list if it sets list fields).
  default_list_constraints    = [for p in local.default_list_policies : p.constraint]
  default_boolean_constraints = [for p in local.default_boolean_policies : p.constraint]
  override_is_list = {
    for c, o in var.org_policy_overrides : c => (
      contains(local.default_list_constraints, c) ||
      (!contains(local.default_boolean_constraints, c) && (o.allowed_values != null || o.denied_values != null || o.allow_all != null || o.deny_all != null))
    )
  }

  effective_list_policies = concat(
    [
      for p in local.default_list_policies : (
        contains(keys(var.org_policy_overrides), p.constraint) ? {
          constraint     = p.constraint
          allowed_values = var.org_policy_overrides[p.constraint].allowed_values
          denied_values  = var.org_policy_overrides[p.constraint].denied_values
          allow_all      = var.org_policy_overrides[p.constraint].allow_all
          deny_all       = var.org_policy_overrides[p.constraint].deny_all
        } : p
      ) if !try(var.org_policy_overrides[p.constraint].disabled, false)
    ],
    [
      for c, o in var.org_policy_overrides : {
        constraint     = c
        allowed_values = o.allowed_values
        denied_values  = o.denied_values
        allow_all      = o.allow_all
        deny_all       = o.deny_all
      } if local.override_is_list[c] && !contains(local.default_list_constraints, c) && !o.disabled
    ],
  )

  effective_boolean_policies = concat(
    [
      for p in local.default_boolean_policies : {
        constraint = p.constraint
        enforce    = try(coalesce(var.org_policy_overrides[p.constraint].enforce, p.enforce), p.enforce)
      } if !try(var.org_policy_overrides[p.constraint].disabled, false)
    ],
    [
      for c, o in var.org_policy_overrides : { constraint = c, enforce = coalesce(o.enforce, true) }
      if !local.override_is_list[c] && !contains(local.default_boolean_constraints, c) && !o.disabled
    ],
  )
}

# G9: opt-in IAM deny policies at the org node — a coarse, allow-independent
# backstop for sensitive permissions (evaluated before allow). Default [] = none.
#
# Guardrail ownership (N2/H3): in the default guardrail_owner_mode = "separate"
# this stage does NOT manage deny policies — its apply identity holds no
# roles/iam.denyAdmin (gcp-bootstrap), so it could not delete the containment
# policy that constrains it. It outputs the policies as gcloud-ready specs
# (output guardrail_deny_policy_specs) for the guardrail owner (the
# <prefix>-guardrails-apply SA, impersonated by a PAM-gated group) to apply; see
# docs/runbooks/production-hardening.md. "organization" = legacy in-stage apply.
locals {
  managed_deny_policies = concat(local.containment_deny_policy, var.iam_deny_policies)

  guardrail_deny_policy_specs = {
    for p in local.managed_deny_policies : p.name => jsonencode({
      displayName = try(coalesce(p.display_name), p.name)
      rules = [
        for r in p.rules : {
          description = try(coalesce(r.description), "")
          denyRule = merge(
            {
              deniedPrincipals     = r.denied_principals
              deniedPermissions    = r.denied_permissions
              exceptionPrincipals  = try(r.exception_principals, null) == null ? [] : r.exception_principals
              exceptionPermissions = try(r.exception_permissions, null) == null ? [] : r.exception_permissions
            },
            r.denial_condition == null ? {} : {
              denialCondition = {
                title       = try(r.denial_condition.title, null)
                description = try(r.denial_condition.description, null)
                expression  = r.denial_condition.expression
              }
            },
          )
        }
      ]
    })
  }
}

module "iam_deny" {
  source = "../../iam/deny-policy"

  parent        = urlencode("cloudresourcemanager.googleapis.com/organizations/${module.organization.organization_id}")
  deny_policies = var.guardrail_owner_mode == "organization" ? local.managed_deny_policies : []
}

# Folder-level Organization Policies for Production
module "prod_folder_policies" {
  source = "../../governance/org-policy"
  for_each = {
    for env_key in var.strict_folder_policy_environment_keys :
    env_key => module.organization.folders[env_key]
    if contains(keys(module.organization.folders), env_key)
  }

  parent = each.value.name

  prefer_managed_constraints = var.prefer_managed_constraints

  list_policies = []

  boolean_policies = [
    {
      constraint = "compute.disableNestedVirtualization"
      enforce    = true
    },
    {
      constraint = "compute.disableGuestAttributesAccess"
      enforce    = true
    },
    {
      constraint = "compute.requireOsLogin"
      enforce    = true
    },
    {
      # Network Security: Force traffic through Cloud NAT / Load Balancers
      constraint = "compute.disableInternetGatewayUse"
      enforce    = true
    }
  ]
}

# CIS GCP 4.4 exemptions: folders that may not use OS Login (e.g. workloads that
# manage SSH keys in metadata) get compute.requireOsLogin = false, overriding the
# org-wide default. Strict folders can never be exempted (variable validation).
module "os_login_exemptions" {
  source = "../../governance/org-policy"
  for_each = var.enforce_os_login ? {
    for env_key in var.os_login_exempt_environment_keys :
    env_key => module.organization.folders[env_key]
    if contains(keys(module.organization.folders), env_key)
  } : {}

  parent        = each.value.name
  list_policies = []

  # Must match the org-node policy: overriding the managed constraint needs the
  # managed name, the legacy one needs the legacy name.
  prefer_managed_constraints = var.prefer_managed_constraints

  boolean_policies = [
    {
      constraint = "compute.requireOsLogin"
      enforce    = false
    },
  ]
}

# Organization logging settings (opt-in): where the _Default/_Required buckets
# of NEW projects are created (data residency) and the CMEK for them. The org's
# Cloud Logging service account (output logging_organization_service_account)
# needs roles/cloudkms.cryptoKeyEncrypterDecrypter on the key BEFORE kms_key_name
# is set, or the settings update fails.
resource "google_logging_organization_settings" "this" {
  count = var.enable_logging_organization_settings ? 1 : 0

  organization         = var.org_id
  storage_location     = coalesce(var.logging_settings_storage_location, var.default_region)
  kms_key_name         = var.logging_settings_kms_key_name
  disable_default_sink = false
}

# Principal access boundary (opt-in): the automation service accounts in the
# admin project may only use their permissions on resources in this
# organization (allowed_resources to widen). Needs the gcp-bootstrap
# enable_principal_access_boundary input. Validate on a non-production org.
module "automation_boundary" {
  source = "../../iam/principal-access-boundary"
  count  = var.enable_principal_access_boundary ? 1 : 0

  organization_id   = var.org_id
  allowed_resources = var.principal_access_boundary_allowed_resources
  project_bindings  = { admin = var.admin_project_id }
}

# Essential Contacts
resource "google_essential_contacts_contact" "security" {
  count = var.security_contact_email != null ? 1 : 0

  parent                              = "organizations/${var.org_id}"
  email                               = var.security_contact_email
  language_tag                        = "en-US"
  notification_category_subscriptions = ["SECURITY", "TECHNICAL", "LEGAL", "PRIVACY", "ALL"]
}

resource "google_essential_contacts_contact" "billing" {
  count = var.billing_contact_email != null ? 1 : 0

  parent                              = "organizations/${var.org_id}"
  email                               = var.billing_contact_email
  language_tag                        = "en-US"
  notification_category_subscriptions = ["BILLING"]
}

# Org Budget
module "org_budget" {
  count  = var.monthly_budget_amount > 0 ? 1 : 0
  source = "../../governance/billing"

  billing_account      = var.billing_account
  project_id           = var.admin_project_id
  project_name         = "${var.project_prefix}-org"
  monthly_budget_limit = var.monthly_budget_amount
  currency_code        = var.budget_currency
  kms_key_name         = module.cmek.key_names["billing-alerts"]
  region               = var.default_region

  # Monitor the entire Billing Account by defaulting 'projects' to empty (null)
  # projects = ["projects/${var.admin_project_number}"]
}

# FinOps: Billing Data Export
# -----------------------------------------------------------------------------
resource "google_bigquery_dataset" "billing_export" {
  dataset_id                  = "billing_export"
  friendly_name               = "Billing Data Export"
  description                 = "Dataset for Cloud Billing export data"
  location                    = var.default_region
  project                     = var.admin_project_id
  default_table_expiration_ms = null # Billing data should be persisted

  default_encryption_configuration {
    kms_key_name = module.cmek.key_names["billing-export"]
  }

  labels = {
    purpose    = "billing-export"
    managed-by = "terraform"
  }

  # Prevent accidental destruction of billing export data.
  # BigQuery datasets with tables ARE destroyed by 'terraform destroy' even without
  # force_destroy = true (unlike GCS buckets which block non-empty deletion).
  # To tear down: manually delete tables, then remove this block and apply first.
  lifecycle {
    prevent_destroy = true
  }
}

# Grant the Cloud Billing service agent permission to write billing data into
# the dataset. Without this IAM binding the billing export silently fails to
# populate the table even though the dataset exists.
# Service agent email format: serviceAccount:billing-export@system.gserviceaccount.com
# Reference: https://cloud.google.com/billing/docs/how-to/export-data-bigquery-setup
resource "google_bigquery_dataset_iam_member" "billing_export_writer" {
  project    = var.admin_project_id
  dataset_id = google_bigquery_dataset.billing_export.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:billing-export@system.gserviceaccount.com"
}
