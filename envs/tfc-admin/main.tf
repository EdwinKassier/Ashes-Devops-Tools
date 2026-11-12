# tfc-admin: declare the whole Terraform Cloud workspace layer as code.
#
# Workspaces, projects, VCS wiring + trigger patterns, explicit remote-state
# sharing, health assessments, dynamic-credential env vars, shared variable sets,
# least-privilege team access and an optional OPA policy set are derived from the same
# config/landing-zone.yaml the cloud roots read (config.tf), so a new
# environment or cloud is a reviewed one-file change, not console clicking. Apply it FIRST (the tfc-admin workspace
# itself is created by hand once, then it manages all the others; optionally it
# adopts itself via manage_tfc_admin_workspace). It never applies cloud
# infrastructure and declares no cloud provider.
#
# Cloud selection: enable_gcp / enable_aws / enable_saas (else gcp/aws/saas
# .enabled in the config file; all default false; at least one must be enabled)
# decide which workspaces exist, so an AWS-only or SaaS-only adopter gets no
# dead gcp-* workspaces.

locals {
  # Repo directories each root reads, keyed by the catalog `dir`: every module
  # it composes, directly or through a stage (the transitive closure of its
  # local `source = "../..."` references), plus any other directory it reads
  # files from. A module-only PR then queues a plan only on the workspaces
  # whose root actually composes that module, not on every workspace of the
  # cloud. trigger_patterns replace the working-directory default, so the
  # root's own dir and the estate config files are added in module.workspace.
  # scripts/check-consistency.sh recomputes the module closure of every root
  # and fails when an entry here is missing or stale.
  root_trigger_dirs = {
    "envs/aws/backup" = [
      "modules/aws/backup/backup-org-policy",
      "modules/aws/backup/backup-vault",
      "modules/aws/data/kms-key",
      "modules/aws/stages/backup",
    ]
    "envs/aws/identity" = [
      "modules/aws/iam/iam-identity-center",
    ]
    "envs/aws/network" = [
      "modules/aws/network/ipam",
      "modules/aws/network/network-access-analyzer",
      "modules/aws/network/network-firewall",
      "modules/aws/network/route53-resolver",
      "modules/aws/network/transit-gateway",
      "modules/aws/network/vpc",
      "modules/aws/network/vpc-endpoints",
      "modules/aws/network/vpn",
      "modules/aws/ops/cloudwatch",
      "modules/aws/stages/network-hub",
    ]
    "envs/aws/organization" = [
      "modules/aws/governance/account",
      "modules/aws/governance/cost-governance",
      "modules/aws/governance/iam-organizations-features",
      "modules/aws/governance/organization",
      "modules/aws/governance/organization-policy",
      "modules/aws/iam/tfc-management-roles",
      "modules/aws/iam/tfc-oidc-baseline",
      "modules/aws/security/config-org",
      "modules/aws/security/config-recorder-stackset",
      "modules/aws/stages/organization",
    ]
    "envs/aws/security" = [
      "modules/aws/data/kms-key",
      "modules/aws/data/log-archive-bucket",
      "modules/aws/governance/service-quotas",
      "modules/aws/iam/iam-role",
      "modules/aws/ops/systems-manager",
      "modules/aws/security/access-analyzer-org",
      "modules/aws/security/cloudtrail-org",
      "modules/aws/security/config-org",
      "modules/aws/security/firewall-manager-org",
      "modules/aws/security/guardduty-org",
      "modules/aws/security/incident-response",
      "modules/aws/security/org-security-service",
      "modules/aws/security/security-delegated-admin",
      "modules/aws/security/security-notifications",
      "modules/aws/security/securityhub-org",
      "modules/aws/security/securitylake",
      "modules/aws/stages/security",
    ]
    "envs/aws/shared-services" = [
      "modules/aws/data/private-ca",
      "modules/aws/security/secrets-baseline",
      "modules/aws/stages/shared-services",
    ]
    "envs/aws/workload" = [
      "modules/aws/compute/ecs-fargate",
      "modules/aws/data/ecr",
      "modules/aws/data/rds-aurora",
      "modules/aws/governance/account-baseline",
      "modules/aws/iam/iam-role",
      "modules/aws/network/load-balancer",
      "modules/aws/network/vpc",
      "modules/aws/ops/cloudwatch",
      "modules/aws/ops/systems-manager",
      "modules/aws/security/edge-security",
      "modules/aws/stages/app-services",
      "modules/aws/stages/workload",
    ]
    "envs/gcp/bootstrap" = [
      "modules/gcp/iam/service-account",
      "modules/gcp/iam/workload-identity",
      "modules/gcp/project",
      "modules/gcp/stages/bootstrap",
    ]
    "envs/gcp/guardrails" = [
      "modules/gcp/iam/deny-policy",
      "modules/gcp/stages/guardrails",
    ]
    "envs/gcp/network-hub" = [
      "modules/gcp/monitoring/alert-policy",
      "modules/gcp/network/cloud-armor",
      "modules/gcp/network/dns",
      "modules/gcp/network/hierarchical-firewall",
      "modules/gcp/network/interconnect",
      "modules/gcp/network/nat",
      "modules/gcp/network/ncc-hub",
      "modules/gcp/network/ncc-spoke",
      "modules/gcp/network/network-firewall",
      "modules/gcp/network/private-service-access",
      "modules/gcp/network/private-service-connect",
      "modules/gcp/network/secure-web-proxy",
      "modules/gcp/network/subnet",
      "modules/gcp/network/tiered-vpc",
      "modules/gcp/network/vpc",
      "modules/gcp/network/vpc-peering",
      "modules/gcp/network/vpc-sc",
      "modules/gcp/network/vpn",
      "modules/gcp/stages/dns-anchor",
      "modules/gcp/stages/net-hub",
      "modules/gcp/stages/network-hub",
    ]
    "envs/gcp/organization" = [
      "modules/gcp/governance/billing",
      "modules/gcp/governance/cloud-audit-logs",
      "modules/gcp/governance/kms",
      "modules/gcp/governance/org-policy",
      "modules/gcp/governance/scc",
      "modules/gcp/governance/tags",
      "modules/gcp/iam/deny-policy",
      "modules/gcp/iam/organization",
      "modules/gcp/iam/principal-access-boundary",
      "modules/gcp/monitoring/control-plane",
      "modules/gcp/stages/guardrails",
      "modules/gcp/stages/organization",
    ]
    "envs/gcp/projects" = [
      "modules/gcp/project",
      "modules/gcp/stages/projects",
    ]
    "envs/gcp/workload" = [
      # Not a module: envs/gcp/workload/config.tf reads the preset YAML files.
      "examples/presets",
      "modules/gcp/artifact-registry",
      "modules/gcp/backup/backup-plan",
      "modules/gcp/backup/backup-vault",
      "modules/gcp/compute/cloud-run",
      "modules/gcp/compute/cloud-run-job",
      "modules/gcp/compute/gke-autopilot",
      "modules/gcp/data/cloud-sql",
      "modules/gcp/data/secret-manager",
      "modules/gcp/governance/billing",
      "modules/gcp/governance/kms",
      "modules/gcp/monitoring/alert-policy",
      "modules/gcp/monitoring/slo",
      "modules/gcp/network/app-ingress",
      "modules/gcp/network/cloud-armor",
      "modules/gcp/network/dns",
      "modules/gcp/network/nat",
      "modules/gcp/network/ncc-spoke",
      "modules/gcp/network/network-firewall",
      "modules/gcp/network/private-service-access",
      "modules/gcp/network/private-service-connect",
      "modules/gcp/network/shared-vpc-service",
      "modules/gcp/network/subnet",
      "modules/gcp/network/tiered-vpc",
      "modules/gcp/network/vpc",
      "modules/gcp/network/vpc-flow-logs",
      "modules/gcp/network/vpc-peering",
      "modules/gcp/network/vpc-sc",
      "modules/gcp/ops/os-config",
      "modules/gcp/project",
      "modules/gcp/stages/app-services",
      "modules/gcp/stages/environment",
      "modules/gcp/stages/net-spoke",
      "modules/gcp/stages/workload",
    ]
    "envs/saas" = [
      "modules/saas/stages/saas-workload",
      "modules/supabase/environment",
      "modules/supabase/project",
      "modules/supabase/settings",
      "modules/supabase/vault-secrets",
      "modules/vercel/project",
    ]
    "envs/tfc-admin" = [
      "modules/tfc/workspace",
    ]
  }

  # ── Workspace catalog ─────────────────────────────────────────────────────
  # The one hand-maintained workspace inventory. Every other workspace list in
  # this root (the workspace set, the remote-state consumer graph, the run-
  # trigger DAG, the multi-account alias lists, the management-default roots and
  # the security-only workspaces) is derived from it, so a new root is one entry
  # here (docs/architecture/adding-a-cloud.md). Keyed by workspace name, or by
  # the name prefix of a per_environment family. Fields:
  #   dir, cloud, desc, tags  workspace settings; "{env}" in desc / tags is
  #                           replaced with the environment of a family member
  #   per_environment         expand into "<key>-<env>" per configured
  #                           environment of the cloud (catalog_environments)
  #   upstreams               run-trigger sources: direct DAG edges only (the
  #                           transitive reduction), so a downstream workspace
  #                           is queued once per upstream change. The tfc-admin
  #                           workspace name marks a DAG root (phase-0 roots)
  #   reads                   upstream states read via terraform_remote_state
  #                           (envs/**): the explicit remote-state consumer graph
  #   aws_member_aliases      member-account provider aliases of a multi-account
  #                           root (alias == aws-organization account key, see
  #                           envs/aws/{security,backup}/providers.tf); each gets
  #                           TFC_AWS_*_<alias> dynamic-credential env vars
  #   aws_management_account  the root's DEFAULT provider is the management
  #                           (payer) account
  #   security_only           security-team project, no shared variable set,
  #                           never auto-applies (gcp-guardrails)
  catalog = merge(local.catalog_roots, local.catalog_platform)
  catalog_roots = {
    "gcp-bootstrap" = {
      dir       = "envs/gcp/bootstrap", cloud = "gcp", desc = "GCP phase-0: admin project, Terraform admin SA, WIF pools", tags = ["cloud:gcp", "layer:bootstrap"]
      upstreams = [var.tfc_admin_workspace_name]
    }
    "gcp-organization" = {
      dir       = "envs/gcp/organization", cloud = "gcp", desc = "GCP org: folders, org policy, KMS, audit, billing", tags = ["cloud:gcp", "layer:control-plane"]
      upstreams = ["gcp-bootstrap"], reads = ["gcp-bootstrap"]
    }
    "gcp-projects" = {
      dir       = "envs/gcp/projects", cloud = "gcp", desc = "GCP host/spoke projects", tags = ["cloud:gcp", "layer:control-plane"]
      upstreams = ["gcp-organization"], reads = ["gcp-bootstrap", "gcp-organization"]
    }
    "gcp-network-hub" = {
      dir       = "envs/gcp/network-hub", cloud = "gcp", desc = "GCP hub VPC, DNS anchor, hub VPC-SC", tags = ["cloud:gcp", "layer:control-plane"]
      upstreams = ["gcp-projects"], reads = ["gcp-organization", "gcp-projects"]
    }
    # Security-team workspace: org IAM deny policies (admin containment). Reads
    # no state and is triggered by nothing.
    "gcp-guardrails" = {
      dir           = "envs/gcp/guardrails", cloud = "gcp", desc = "GCP org IAM deny policies (security team)", tags = ["cloud:gcp", "layer:control-plane", "owner:security"]
      security_only = true
    }
    "gcp-workload" = {
      dir             = "envs/gcp/workload", cloud = "gcp", desc = "GCP {env} workload", tags = ["cloud:gcp", "layer:workload", "env:{env}"]
      per_environment = true
      upstreams       = ["gcp-network-hub"], reads = ["gcp-organization", "gcp-projects", "gcp-network-hub"]
    }
    "aws-organization" = {
      dir       = "envs/aws/organization", cloud = "aws", desc = "AWS org, SCP/RCP, account factory", tags = ["cloud:aws", "layer:control-plane"]
      upstreams = [var.tfc_admin_workspace_name], aws_management_account = true
    }
    "aws-security" = {
      dir                = "envs/aws/security", cloud = "aws", desc = "AWS security baseline + log archive", tags = ["cloud:aws", "layer:control-plane"]
      upstreams          = ["aws-organization"], reads = ["aws-organization"], aws_management_account = true
      aws_member_aliases = ["security_tooling", "log_archive", "forensics"]
    }
    "aws-network" = {
      dir       = "envs/aws/network", cloud = "aws", desc = "AWS shared networking (TGW/IPAM)", tags = ["cloud:aws", "layer:control-plane"]
      upstreams = ["aws-organization"], reads = ["aws-organization"]
    }
    "aws-identity" = {
      dir       = "envs/aws/identity", cloud = "aws", desc = "AWS IAM Identity Center", tags = ["cloud:aws", "layer:control-plane"]
      upstreams = ["aws-organization"], reads = ["aws-organization"]
    }
    "aws-shared-services" = {
      dir       = "envs/aws/shared-services", cloud = "aws", desc = "AWS shared platform services", tags = ["cloud:aws", "layer:control-plane"]
      upstreams = ["aws-organization"], reads = ["aws-organization"]
    }
    "aws-backup" = {
      dir                = "envs/aws/backup", cloud = "aws", desc = "AWS centralized backup", tags = ["cloud:aws", "layer:control-plane"]
      upstreams          = ["aws-organization"], reads = ["aws-organization"], aws_management_account = true
      aws_member_aliases = ["backup"]
    }
    "aws-workload" = {
      dir             = "envs/aws/workload", cloud = "aws", desc = "AWS {env} workload", tags = ["cloud:aws", "layer:workload", "env:{env}"]
      per_environment = true
      upstreams       = ["aws-network", "aws-security"], reads = ["aws-organization", "aws-network", "aws-security"]
    }
    # saas-<name> per saas.workspaces entry.
    "saas" = {
      dir             = "envs/saas", cloud = "saas", desc = "SaaS {env} (Supabase/Vercel)", tags = ["cloud:saas", "layer:workload"]
      per_environment = true
    }
  }
  # Optional self-management of the hand-created tfc-admin workspace (adopted
  # via the import block below, never created; manage_tfc_admin_workspace).
  # Merged in only when managed, so an unmanaged tfc_admin_workspace_name never
  # becomes a catalog key (a managed one that collides fails input_contract).
  catalog_platform = var.manage_tfc_admin_workspace ? {
    (var.tfc_admin_workspace_name) = {
      dir = "envs/tfc-admin", cloud = "platform", desc = "TFC workspace layer (this root)", tags = ["cloud:tfc", "layer:control-plane"]
    }
  } : {}

  # Which clouds' entries exist, and each cloud's environment list for its
  # per_environment families.
  catalog_cloud_enabled = {
    gcp      = local.enable_gcp
    aws      = local.enable_aws
    saas     = local.enable_saas
    platform = var.manage_tfc_admin_workspace
  }
  catalog_environments = {
    gcp      = local.gcp_environment_keys
    aws      = keys(local.aws_environments)
    saas     = local.saas_workspaces
    platform = []
  }

  # Every entry with every field (omitted fields take their defaults).
  catalog_entries = {
    for k, e in local.catalog : k => {
      dir                    = e.dir
      cloud                  = e.cloud
      desc                   = e.desc
      tags                   = tolist(e.tags)
      per_environment        = try(e.per_environment, false)
      upstreams              = tolist(try(e.upstreams, []))
      reads                  = tolist(try(e.reads, []))
      aws_member_aliases     = tolist(try(e.aws_member_aliases, []))
      aws_management_account = try(e.aws_management_account, false)
      security_only          = try(e.security_only, false)
    }
  }

  # The managed workspaces: the enabled clouds' entries, each per_environment
  # family expanded into <key>-<env> (environment = null for the others).
  # aws-organization and aws-security are always created with AWS; the other
  # AWS layers follow aws_layers (aws.layers). Every grant, trigger, consumer
  # edge and variable below derives from this map, so a dropped layer leaves
  # no trace.
  aws_required_layers = ["aws-organization", "aws-security"]
  workspaces = merge(
    {
      for k, e in local.catalog_entries : k => merge(e, { environment = null })
      if !e.per_environment && local.catalog_cloud_enabled[e.cloud] && (
        e.cloud != "aws" || contains(local.aws_required_layers, k) || contains(local.aws_layers, trimprefix(k, "aws-"))
      )
    },
    merge([
      for k, e in local.catalog_entries : {
        for env in local.catalog_environments[e.cloud] : "${k}-${env}" => merge(e, {
          desc        = replace(e.desc, "{env}", env)
          tags        = [for t in e.tags : replace(t, "{env}", env)]
          environment = env
        })
      } if e.per_environment && local.catalog_cloud_enabled[e.cloud]
    ]...),
  )

  workspace_names = toset(keys(local.workspaces))

  is_control_plane = {
    for k, w in local.workspaces :
    k => contains(w.tags, "layer:control-plane") || contains(w.tags, "layer:bootstrap")
  }

  # Per-environment family prefix by cloud (catalog key of its per_environment
  # entry): gcp-workload, aws-workload, saas. Ungated by catalog_cloud_enabled,
  # like the environment lists it is combined with.
  catalog_family = {
    for k, e in local.catalog_entries : e.cloud => k if e.per_environment
  }

  # Per-environment family members by cloud.
  gcp_workload_names   = [for k, w in local.workspaces : k if w.cloud == "gcp" && w.environment != null]
  aws_workload_names   = [for k, w in local.workspaces : k if w.cloud == "aws" && w.environment != null]
  saas_workspace_names = [for k, w in local.workspaces : k if w.cloud == "saas" && w.environment != null]

  # ── Remote-state consumer graph ───────────────────────────────────────────
  # The catalog's reads, inverted: producer => the workspaces that read it.
  # global_remote_state is false everywhere, so only these edges (plus
  # extra_remote_state_consumers) can read a state file.
  base_consumers = {
    for producer in local.workspace_names : producer => [for k, w in local.workspaces : k if contains(w.reads, producer)]
  }

  # tfc-admin reads gcp-bootstrap / aws-organization outputs (tfe_outputs) only
  # when the *_outputs_from_tfc toggles are on; grant it read access then.
  tfc_admin_reads = compact([
    var.gcp_bootstrap_outputs_from_tfc ? "gcp-bootstrap" : "",
    var.aws_organization_outputs_from_tfc ? "aws-organization" : "",
  ])
  tfc_admin_workspace_id = length(local.tfc_admin_reads) == 0 ? null : (
    var.manage_tfc_admin_workspace ? module.workspace[var.tfc_admin_workspace_name].id : data.tfe_workspace.tfc_admin[0].id
  )

  consumer_names = {
    for producer in local.workspace_names : producer => distinct([
      for c in concat(
        lookup(local.base_consumers, producer, []),
        lookup(var.extra_remote_state_consumers, producer, []),
      ) : c if contains(local.workspace_names, c)
    ])
  }

  consumer_ids = {
    for producer, consumers in local.consumer_names : producer => concat(
      [for c in consumers : module.workspace[c].id],
      contains(local.tfc_admin_reads, producer) && !contains(consumers, var.tfc_admin_workspace_name) ? [local.tfc_admin_workspace_id] : [],
    )
  }

  # ── Dynamic provider credentials ──────────────────────────────────────────
  # Explicit input maps win over values read from upstream outputs. Upstreams
  # are read through their single non-sensitive `contract` output
  # (scripts/check-contracts.sh); a state from before that output existed falls
  # back to the same keys as individual outputs until v1.0 (UPGRADING.md).
  gcp_bootstrap_outputs = try(data.tfe_outputs.gcp_bootstrap[0].nonsensitive_values.contract, data.tfe_outputs.gcp_bootstrap[0].nonsensitive_values, {})

  gcp_workload_provider_name = coalesce(var.gcp_workload_provider_name, try(local.gcp_bootstrap_outputs.tfc_workload_provider_name, null), "unset")

  # Per-environment workload SAs, derived so a NEW environment's workspace gets
  # its TFC_GCP_* env vars in the same tfc-admin apply that creates it. Naming is
  # gcp-bootstrap's (modules/gcp/stages/bootstrap/service_accounts.tf):
  # <prefix>-wl-<env>-{plan,apply}@<admin_project_id>.iam.gserviceaccount.com.
  # The admin project ID carries a random suffix, so it comes from the existing
  # gcp-bootstrap outputs (static after phase 0), never from config. Greenfield
  # still needs the phase-0 pass: until gcp-bootstrap has applied there are no
  # outputs and nothing is derived. Precedence: derived < bootstrap outputs <
  # explicit variables (check.derived_gcp_service_accounts_match_bootstrap
  # flags a derived email that disagrees with the outputs).
  gcp_admin_project_id = try(tostring(local.gcp_bootstrap_outputs.admin_project_id), null)
  derive_gcp_workload_sas = (
    local.enable_gcp && var.gcp_bootstrap_outputs_from_tfc &&
    local.gcp_project_prefix != null && local.gcp_admin_project_id != null
  )
  gcp_workload_account_ids = local.enable_gcp && local.gcp_project_prefix != null ? {
    for env in local.gcp_environment_keys : env => {
      plan  = "${local.gcp_project_prefix}-wl-${env}-plan"
      apply = "${local.gcp_project_prefix}-wl-${env}-apply"
    }
  } : {}
  # GCP service-account IDs are 6-30 characters; "-apply" is the longer suffix.
  gcp_workload_account_ids_too_long = sort([for env, ids in local.gcp_workload_account_ids : ids.apply if length(ids.apply) > 30])
  derived_gcp_plan_sas = local.derive_gcp_workload_sas ? {
    for env, ids in local.gcp_workload_account_ids : "${local.catalog_family.gcp}-${env}" => "${ids.plan}@${local.gcp_admin_project_id}.iam.gserviceaccount.com"
  } : {}
  derived_gcp_apply_sas = local.derive_gcp_workload_sas ? {
    for env, ids in local.gcp_workload_account_ids : "${local.catalog_family.gcp}-${env}" => "${ids.apply}@${local.gcp_admin_project_id}.iam.gserviceaccount.com"
  } : {}
  bootstrap_gcp_plan_sas  = try(tomap(local.gcp_bootstrap_outputs.tfc_plan_service_accounts), {})
  bootstrap_gcp_apply_sas = try(tomap(local.gcp_bootstrap_outputs.tfc_apply_service_accounts), {})
  derived_gcp_sa_mismatches = sort(concat(
    [for ws, e in local.derived_gcp_plan_sas : "${ws} plan (${e} vs ${local.bootstrap_gcp_plan_sas[ws]})" if contains(keys(local.bootstrap_gcp_plan_sas), ws) && try(local.bootstrap_gcp_plan_sas[ws] != e, true)],
    [for ws, e in local.derived_gcp_apply_sas : "${ws} apply (${e} vs ${local.bootstrap_gcp_apply_sas[ws]})" if contains(keys(local.bootstrap_gcp_apply_sas), ws) && try(local.bootstrap_gcp_apply_sas[ws] != e, true)],
  ))

  gcp_plan_sas = merge(
    local.derived_gcp_plan_sas,
    local.bootstrap_gcp_plan_sas,
    var.gcp_plan_service_accounts,
  )
  gcp_apply_sas = merge(
    local.derived_gcp_apply_sas,
    local.bootstrap_gcp_apply_sas,
    var.gcp_apply_service_accounts,
  )

  # Env-var descriptions (shared by every workspace that gets the var).
  credential_env_descriptions = {
    TFC_GCP_PROVIDER_AUTH               = "Enable HCP Terraform GCP dynamic credentials (WIF)."
    TFC_GCP_WORKLOAD_PROVIDER_NAME      = "Full WIF provider resource name (projects/<num>/locations/global/workloadIdentityPools/<pool>/providers/<provider>)."
    TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL  = "Read-only SA impersonated during plan."
    TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL = "SA impersonated during apply."
    TFC_AWS_PROVIDER_AUTH               = "Enable HCP Terraform AWS dynamic credentials (OIDC)."
    TFC_AWS_PLAN_ROLE_ARN               = "Read-only IAM role assumed during plan."
    TFC_AWS_APPLY_ROLE_ARN              = "IAM role assumed during apply."
  }

  # A GCP workspace gets dynamic credentials only when the WIF provider name is
  # known AND it has a plan or apply SA; nothing is set otherwise.
  gcp_credential_env = {
    for ws, w in local.workspaces : ws => {
      for k, v in {
        TFC_GCP_PROVIDER_AUTH               = "true"
        TFC_GCP_WORKLOAD_PROVIDER_NAME      = local.gcp_workload_provider_name
        TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL  = try(local.gcp_plan_sas[ws], null)
        TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL = try(local.gcp_apply_sas[ws], null)
      } : k => { value = v, category = "env", hcl = false, sensitive = false, description = local.credential_env_descriptions[k] } if v != null
    }
    if w.cloud == "gcp" && local.gcp_workload_provider_name != "unset" && (try(local.gcp_plan_sas[ws], null) != null || try(local.gcp_apply_sas[ws], null) != null)
  }

  aws_organization_outputs = try(data.tfe_outputs.aws_organization[0].nonsensitive_values.contract, data.tfe_outputs.aws_organization[0].nonsensitive_values, {})
  aws_output_plan_roles    = try(tomap(local.aws_organization_outputs.tfc_plan_role_arns), {})
  aws_output_apply_roles   = try(tomap(local.aws_organization_outputs.tfc_apply_role_arns), {})
  # Dedicated per-workspace management roles (aws-security, aws-backup) from
  # aws-organization; they replace the shared phase-0 role for those roots.
  aws_output_mgmt_plan_roles  = try(tomap(local.aws_organization_outputs.tfc_management_plan_role_arns), {})
  aws_output_mgmt_apply_roles = try(tomap(local.aws_organization_outputs.tfc_management_apply_role_arns), {})

  # Roots whose DEFAULT provider is the management (payer) account (catalog
  # aws_management_account). Their default credentials are the phase-0
  # management-account role, never a member role.
  aws_management_workspaces = [for k, e in local.catalog_entries : k if e.aws_management_account]

  # Multi-account roots and their member-account provider aliases (catalog
  # aws_member_aliases; alias name == aws-organization account key, see
  # envs/aws/{security,backup}/providers.tf). Each alias authenticates directly
  # as that account's tfc-plan / tfc-apply role through a TFC
  # multiple-configuration dynamic credential.
  aws_alias_accounts = {
    for k, e in local.catalog_entries : k => e.aws_member_aliases if length(e.aws_member_aliases) > 0
  }

  # Single-account workspace => account key. Sources, lowest precedence first:
  # aws-organization's tfc_workspace_bindings (account key => workspace names,
  # inverted), environments[*].aws_account_key for aws-workload-<env>, then
  # var.aws_workspace_account_keys. Management-default roots are excluded: their
  # bindings exist only to trust the alias roles.
  aws_bound_workspaces = {
    for pair in flatten([
      for acct, wss in try(tomap(local.aws_organization_outputs.tfc_workspace_bindings), {}) : [
        for ws in wss : { ws = ws, acct = acct }
      ]
    ]) : pair.ws => pair.acct...
  }
  aws_workspace_accounts = {
    for ws, acct in merge(
      { for ws, accts in local.aws_bound_workspaces : ws => sort(accts)[0] },
      { for env, e in local.aws_environments : "${local.catalog_family.aws}-${env}" => e.aws_account_key if e.aws_account_key != null },
      var.aws_workspace_account_keys,
    ) : ws => acct if !contains(local.aws_management_workspaces, ws)
  }

  # Per-alias role pairs for the managed multi-account workspaces: explicit
  # aws_alias_role_arns win over the aws-organization outputs.
  aws_alias_roles = {
    for ws, aliases in local.aws_alias_accounts : ws => {
      for a in aliases : a => {
        plan  = try(var.aws_alias_role_arns[ws][a].plan_role_arn, local.aws_output_plan_roles[a], null)
        apply = try(var.aws_alias_role_arns[ws][a].apply_role_arn, local.aws_output_apply_roles[a], null)
      }
    } if contains(local.workspace_names, ws)
  }
  # A multi-account workspace is credential-complete only when every alias has
  # both roles; the derived management default is withheld until then, because
  # TFC would otherwise inject tfc_aws_dynamic_credentials without the aliases
  # the root's providers index.
  aws_aliases_complete = {
    for ws, aliases in local.aws_alias_roles : ws => alltrue([for r in values(aliases) : r.plan != null && r.apply != null])
  }

  # Per workspace: the dedicated management role pair when aws-organization
  # created one, else the shared phase-0 role (aws-organization always uses it).
  aws_management_defaults = {
    for ws in local.aws_management_workspaces : ws => {
      plan  = try(local.aws_output_mgmt_plan_roles[ws], var.aws_management_plan_role_arn)
      apply = try(local.aws_output_mgmt_apply_roles[ws], var.aws_management_apply_role_arn)
    } if contains(local.workspace_names, ws) && lookup(local.aws_aliases_complete, ws, true) &&
    (try(local.aws_output_mgmt_plan_roles[ws], var.aws_management_plan_role_arn) != null)
  }

  aws_plan_roles = merge(
    { for ws, r in local.aws_management_defaults : ws => r.plan },
    {
      for ws, acct in local.aws_workspace_accounts : ws => local.aws_output_plan_roles[acct]
      if try(local.aws_output_plan_roles[acct], null) != null
    },
    var.aws_plan_role_arns,
  )
  aws_apply_roles = merge(
    { for ws, r in local.aws_management_defaults : ws => r.apply },
    {
      for ws, acct in local.aws_workspace_accounts : ws => local.aws_output_apply_roles[acct]
      if try(local.aws_output_apply_roles[acct], null) != null
    },
    var.aws_apply_role_arns,
  )

  # Alias env vars are emitted only for a workspace whose default credentials are
  # set too (a TFC alias configuration without the default one is unusable).
  aws_alias_env = {
    for ws, aliases in local.aws_alias_roles : ws => merge([
      for a, r in aliases : {
        "TFC_AWS_PROVIDER_AUTH_${a}"  = { value = "true", category = "env", hcl = false, sensitive = false, description = "Enable the ${a} AWS dynamic-credential configuration (provider alias aws.${a})." }
        "TFC_AWS_PLAN_ROLE_ARN_${a}"  = { value = r.plan, category = "env", hcl = false, sensitive = false, description = "${a} account tfc-plan role assumed by alias aws.${a} during plan." }
        "TFC_AWS_APPLY_ROLE_ARN_${a}" = { value = r.apply, category = "env", hcl = false, sensitive = false, description = "${a} account tfc-apply role assumed by alias aws.${a} during apply." }
      } if r.plan != null && r.apply != null
    ]...)
    if try(local.aws_plan_roles[ws], null) != null
  }

  aws_credential_env = {
    for ws, w in local.workspaces : ws => merge(
      {
        for k, v in {
          TFC_AWS_PROVIDER_AUTH  = "true"
          TFC_AWS_PLAN_ROLE_ARN  = try(local.aws_plan_roles[ws], null)
          TFC_AWS_APPLY_ROLE_ARN = try(local.aws_apply_roles[ws], null)
        } : k => { value = v, category = "env", hcl = false, sensitive = false, description = local.credential_env_descriptions[k] } if v != null
      },
      lookup(local.aws_alias_env, ws, {}),
    )
    if w.cloud == "aws" && (try(local.aws_plan_roles[ws], null) != null || try(local.aws_apply_roles[ws], null) != null)
  }

  # A multi-account workspace with default credentials but missing alias roles
  # would fail at plan time inside the root; fail here instead.
  aws_incomplete_multi_account = [
    for ws, complete in local.aws_aliases_complete : ws
    if !complete && contains(keys(local.aws_credential_env), ws)
  ]

  # Workload roots declare var.environment; set it from the workspace name so the
  # env is never hand-typed. aws-workload-<env> also gets workload_account_key
  # when environments[env].aws_account_key is set, and enable_network_hub =
  # false when there is no aws-network workspace and no aws.contracts.network
  # (aws_workload_standalone): in hub mode the root reads aws-network's state.
  # Overridable via workspace_variables (or the committed
  # workspace_variables_file); aws_workloads_needing_network rejects an
  # override back to hub mode.
  derived_terraform_vars = merge(
    {
      for ws in local.saas_workspace_names : ws => {
        stack = { value = local.workspaces[ws].environment, category = "terraform", hcl = false, sensitive = false, description = "SaaS stack key in saas.stacks (derived from the workspace name)." }
      }
    },
    {
      for ws in local.gcp_workload_names : ws => {
        environment = { value = local.workspaces[ws].environment, category = "terraform", hcl = false, sensitive = false, description = "Environment key (derived from the workspace name)." }
      }
    },
    {
      for ws in local.aws_workload_names : ws => merge(
        { environment = { value = local.workspaces[ws].environment, category = "terraform", hcl = false, sensitive = false, description = "Environment key (derived from the workspace name)." } },
        try(local.aws_environments[local.workspaces[ws].environment].aws_account_key, null) == null ? {} : {
          workload_account_key = { value = local.aws_environments[local.workspaces[ws].environment].aws_account_key, category = "terraform", hcl = false, sensitive = false, description = "aws-organization account key this workload deploys into (environments[*].aws_account_key or aws.workload_environments[*].account_key)." }
        },
        !local.aws_workload_standalone ? {} : {
          enable_network_hub = { value = "false", category = "terraform", hcl = true, sensitive = false, description = "Standalone VPC: aws.layers has no network layer, so there is no aws-network workspace to attach to." }
        },
      )
    },
  )

  # aws-workload-<env> in hub mode (enable_network_hub, default true) reads the
  # aws-network state unless aws.contracts.network supplies the contract.
  aws_workload_standalone = !contains(local.aws_layers, "network") && !local.cfg.aws_network_contract
  aws_workloads_needing_network = sort([
    for ws in local.aws_workload_names : ws
    if local.aws_workload_standalone && try(lower(trim(local.workspace_vars[ws].enable_network_hub.value, " \t\r\n\"'")), "true") != "false"
  ])

  # ── Committed per-workspace variables (VCS-driven runs) ───────────────────
  workspace_variables_file_path = var.workspace_variables_file == null ? null : (
    startswith(var.workspace_variables_file, "/") ? var.workspace_variables_file : "${path.root}/${var.workspace_variables_file}"
  )
  workspace_variables_file_present = local.workspace_variables_file_path != null && fileexists(coalesce(local.workspace_variables_file_path, "/nonexistent"))
  workspace_variables_file_raw     = local.workspace_variables_file_present ? yamldecode(file(local.workspace_variables_file_path)) : {}

  # Normalise each entry: a bare scalar is a string value; a bare list/map is
  # set as an HCL value (JSON is valid HCL); an object with `value` carries the
  # full {value, category, hcl, description} form.
  file_workspace_variables = {
    for ws, vars in try(local.workspace_variables_file_raw.workspaces, {}) : ws => {
      for k, v in vars : k => {
        value       = can(v.value) ? (can(tostring(v.value)) ? tostring(v.value) : jsonencode(v.value)) : (can(tostring(v)) ? tostring(v) : jsonencode(v))
        category    = can(v.value) ? try(v.category, "terraform") : "terraform"
        hcl         = can(v.value) ? try(v.hcl, !can(tostring(v.value))) : !can(tostring(v))
        sensitive   = can(v.value) ? try(v.sensitive, false) : false
        description = can(v.value) ? try(v.description, null) : "Set from ${var.workspace_variables_file}."
        version     = 1
      }
    }
  }
  # Env vars that make the runner execute code other than the reviewed
  # configuration: the CLI config file under either name (provider
  # installation, credentials helpers), the dynamic loader (LD_*, DYLD_*), the
  # interpreters the run starts (NODE_OPTIONS / NODE_PATH for the vault-secrets
  # provisioner, PYTHON*), shell start-up files (BASH_ENV, ENV), git hooks and
  # transports for module downloads (GIT_*) and PATH. Refused from both the
  # committed file and workspace_variables. A denylist, not an allowlist:
  # workspace_variables is documented to carry provider tokens (TFE_TOKEN,
  # SUPABASE_ACCESS_TOKEN, VERCEL_API_TOKEN), TF_CLI_ARGS_plan
  # (add-environment.md), dynamic-credential overrides and a corporate proxy
  # (UPGRADING.md), and the committed file takes free-form env vars, so no
  # fixed list of names fits. tfc_admin_guard (overridable) flags TFC_* and
  # TF_CLI_ARGS* writes for the security team.
  code_exec_env_pattern = "^(TERRAFORM_CONFIG|TF_CLI_CONFIG_FILE|LD_[A-Z_]+|DYLD_[A-Z_]+|NODE_OPTIONS|NODE_PATH|GIT_[A-Z0-9_]+|BASH_ENV|ENV|PYTHON[A-Z_]+|PATH)$"
  # The committed file must not steer credentials, the CLI or HTTPS either:
  # dynamic-credential env vars (TFC_*), CLI argument injection
  # (TF_CLI_ARGS*), host tokens (TF_TOKEN_*), the tfe provider's host and
  # token (TFE_*), provider auth env vars, Terraform's own controls, and
  # anything that reroutes or re-trusts HTTPS (proxies in any case,
  # SSL_CERT_FILE / SSL_CERT_DIR, NODE_EXTRA_CA_CERTS). tfc-admin derives the
  # legitimate ones; the rest go through workspace_variables.
  reserved_env_pattern = "(^(TFC_|TFE_|TF_CLI_ARGS|TF_TOKEN_|TF_VAR_|TF_WORKSPACE|TF_LOG|AWS_|GOOGLE_|CLOUDSDK_|SUPABASE_|VERCEL_))|(^(SSL_CERT_FILE|SSL_CERT_DIR|NODE_EXTRA_CA_CERTS|(?i:(HTTPS?|ALL|NO)_PROXY))$)|(${local.code_exec_env_pattern})"
  file_reserved_entries = flatten([
    for ws, vars in local.file_workspace_variables : [
      for k, v in vars : "${ws}.${k}"
      if v.category == "env" && can(regex(local.reserved_env_pattern, k))
    ]
  ])
  workspace_variables_exec_entries = flatten([
    for ws, vars in var.workspace_variables : [
      for k, v in vars : "${ws}.${k}"
      if v.category == "env" && can(regex(local.code_exec_env_pattern, k))
    ]
  ])
  file_sensitive_entries = flatten([
    for ws, vars in local.file_workspace_variables : [for k, v in vars : "${ws}.${k}" if v.sensitive]
  ])
  file_bad_categories = flatten([
    for ws, vars in local.file_workspace_variables : [for k, v in vars : "${ws}.${k}" if !contains(["terraform", "env"], v.category)]
  ])
  # The committed file is platform-reviewable; a security_only workspace
  # (gcp-guardrails) takes inputs only from its own security-owned root or from
  # the security team's workspace_variables, never from this file. The one
  # exception is pointing it at this estate's own landing-zone file (the
  # sandbox estate does), which is the file tfc-admin itself reads.
  file_security_only_entries = sort(flatten([
    for ws, vars in local.file_workspace_variables : [
      for k, v in vars : "${ws}.${k}"
      if try(local.workspaces[ws].security_only, false) && !(
        k == "landing_zone_config_path" && v.category == "terraform" && local.estate_landing_zone_path != null &&
        v.value == "../../../${coalesce(local.estate_landing_zone_path, "-")}"
      )
    ]
  ]))

  workspace_vars = {
    for ws in local.workspace_names : ws => merge(
      lookup(local.gcp_credential_env, ws, {}),
      lookup(local.aws_credential_env, ws, {}),
      lookup(local.derived_terraform_vars, ws, {}),
      lookup(local.file_workspace_variables, ws, {}),
      lookup(var.workspace_variables, ws, {}),
    )
  }

  # Execution mode: per-workspace override over the global default.
  execution_modes = {
    for ws in local.workspace_names : ws => lookup(var.workspace_execution_modes, ws, var.execution_mode)
  }

  # ── Projects ──────────────────────────────────────────────────────────────
  # One project per cloud; with split_workload_projects the gcp/aws workload
  # workspaces move to <prefix><cloud>-workloads so access is granted per project.
  # gcp-guardrails always gets its own project (security team only).
  workspace_project_key = {
    for k, w in local.workspaces : k => (
      contains(local.guardrails_workspaces, k) ? "guardrails" : (
        local.split_workload_projects && contains(["gcp", "aws"], w.cloud) && !local.is_control_plane[k] ? "${w.cloud}-workloads" : w.cloud
      )
    )
  }
  project_keys = var.enable_projects ? toset(distinct(values(local.workspace_project_key))) : toset([])

  # Projects that hold at least one control-plane / bootstrap workspace. The
  # guardrails project is not among them: its access model is its own.
  control_plane_projects = toset([for k, p in local.workspace_project_key : p if local.is_control_plane[k] && contains(local.project_keys, p) && p != "guardrails"])

  # Every project except the security-only guardrails project.
  shared_access_projects = setsubtract(local.project_keys, ["guardrails"])

  # ── Team access ────────────────────────────────────────────────
  # The broad platform team never gets fixed write on a control-plane project
  # or on a production workload: write would let one member set a workspace
  # variable (a TF_VAR_* beats config/landing-zone.yaml, a control-plane
  # variable can carry containment or break-glass inputs) and confirm the apply
  # alone. There it gets custom access (runs = platform_team_control_plane_runs,
  # variables read-only), and only the separate approvers team may confirm
  # applies. Projects holding only non-production workloads keep fixed write.
  # A non-production workload that shares a project with the control plane or
  # with a production workload gets write through a workspace-level grant
  # (TFC permissions are additive); a production workload never does.
  platform_custom_access = {
    runs           = var.platform_team_control_plane_runs
    variables      = "read"
    state_versions = "read-outputs"
    sentinel_mocks = "none"
    locking        = false
  }
  # Security team on the guardrails project: queue plans and confirm applies
  # (runs = apply) and lock the workspace; variables stay read-only, like every
  # control-plane grant here ("Variables belong in code", README), so the deny
  # policies change only through a reviewed config/landing-zone.yaml.
  security_custom_access = {
    runs           = "apply"
    variables      = "read"
    state_versions = "read"
    sentinel_mocks = "none"
    locking        = true
  }
  # Release reader on the guardrails project (terraform-apply.yml, gcp-guardrails
  # tags): sees run status and the run's source commit, nothing else. Fixed
  # read would also return the state file, so the grant is custom.
  release_reader_custom_access = {
    runs           = "read"
    variables      = "none"
    state_versions = "none"
    sentinel_mocks = "none"
    locking        = false
  }
  approvers_custom_access = {
    runs           = "apply"
    variables      = "read"
    state_versions = "read"
    sentinel_mocks = "none"
    locking        = true
  }
  # Viewers on projects whose STATE holds secrets (saas: the Supabase database
  # password and service-role key). Fixed read includes the full state file,
  # and read-outputs would also return sensitive outputs, so viewers see runs
  # and variables (sensitive values stay write-only) but no state at all.
  viewer_secret_state_access = {
    runs           = "read"
    variables      = "read"
    state_versions = "none"
    sentinel_mocks = "none"
    locking        = false
  }
  # The platform team on the same projects: the same access. Its usual
  # read-outputs is not enough of a limit there, because the API can still
  # return a sensitive output value. Bridging workloads read the saas outputs
  # with their own saas-outputs-reader team token, not the platform team's.
  platform_secret_state_access = local.viewer_secret_state_access
  # State export team (state-backup.yml): reads state versions, nothing else.
  state_backup_custom_access = {
    runs           = "read"
    variables      = "none"
    state_versions = "read"
    sentinel_mocks = "none"
    locking        = false
  }
  # Drift team (drift-detection.yml): reads the current state version to find
  # the last applied run, then queues a plan-only, refresh-only run on it.
  drift_custom_access = {
    runs           = "plan"
    variables      = "none"
    state_versions = "read"
    sentinel_mocks = "none"
    locking        = false
  }

  # ── Guardrails (security team only) ──────────────────────────
  # gcp-guardrails applies the org IAM deny policies that contain the platform's
  # own automation identity. It sits in its own project where ONLY the security
  # team has access (queue, confirm and discard runs): no platform,
  # approvers or viewer grant. Organization owners keep their implicit access,
  # and tfc-admin itself can still repoint the workspace, so separation of
  # duties also rests on CODEOWNERS for envs/tfc-admin/** (docs/known-gaps.md).
  guardrails_workspaces = [for k, w in local.workspaces : k if w.security_only]
  guardrails_project    = contains(local.project_keys, "guardrails")

  # Workspaces that must never apply without a human confirmation, whatever a
  # future auto-apply setting does for the others.
  never_auto_apply_workspaces = concat(local.guardrails_workspaces, [var.tfc_admin_workspace_name])

  # Non-production gcp-/aws-workload-<env> workspaces: queue_all_runs and
  # auto_apply_run_trigger (enable_nonprod_workload_auto_apply). Trust change:
  # a confirmed upstream apply (gcp-network-hub, aws-network, aws-security)
  # applies these without a further confirmation. Fail-closed: only an
  # environment whose is_production is false qualifies (the environments
  # validation fails the plan when an environment omits the flag).
  explicit_nonprod_workloads = toset(concat(
    [for k in local.gcp_workload_names : k if lookup(local.gcp_production_flags, local.workspaces[k].environment, null) == false],
    [for k in local.aws_workload_names : k if try(local.aws_environments[local.workspaces[k].environment].is_production, null) == false],
  ))
  # Null follows the policy sets: an auto-applied run is only allowed where
  # destroy_guard can stop a stateful delete/replace (fail-safe default).
  enable_nonprod_workload_auto_apply = coalesce(var.enable_nonprod_workload_auto_apply, local.enable_policy_sets)
  nonprod_auto_apply_workloads = local.enable_nonprod_workload_auto_apply ? setsubtract(
    local.explicit_nonprod_workloads,
    setunion(local.production_workloads, toset(local.never_auto_apply_workspaces)),
  ) : toset([])

  # The self-managed tfc-admin workspace is the only member of the platform
  # project. It holds the TFE_TOKEN, so no project grant may confirm its apply:
  # approvers get nothing there. Apply is limited to organization owners and the
  # tfc-admin team (tfe_team_access.tfc_admin).
  tfc_admin_only_projects = var.manage_tfc_admin_workspace && var.enable_projects ? toset([local.workspace_project_key[var.tfc_admin_workspace_name]]) : toset([])

  # The saas project holds the account-wide SUPABASE_ACCESS_TOKEN and
  # VERCEL_API_TOKEN. Its runs are confirmed by saas_approvers_team_id when set,
  # else by the control-plane approvers team. A team that may confirm an apply
  # may also queue a plan (HCP Terraform has no apply-only permission), and a
  # plan can read those tokens.
  saas_projects = setintersection(local.project_keys, toset(["saas"]))
  # Saas projects that the control-plane approvers team confirms.
  control_plane_approved_saas_projects = var.saas_approvers_team_id == null ? local.saas_projects : toset([])

  # A plan is code execution with the workspace's credentials: anyone who may
  # queue a plan, including a CLI speculative plan with their own unreviewed
  # configuration (speculative_enabled = false does not stop those), or a PR
  # speculative plan, can read every variable on the workspace. A workspace is
  # secret-bearing when:
  #   - this root writes a sensitive variable to it (workspace_variables, such
  #     as the TFE_TOKEN of the SaaS bridge), or a variable whose key looks like
  #     a secret (secret_variable_key_pattern) even if it is not marked sensitive;
  #   - it runs the SaaS bridge (enable_saas_secret_bridge, as a Terraform or
  #     TF_VAR_ env variable): its TFE_TOKEN may be set by hand, out of sight;
  #   - the shared variable set carries a sensitive or secret-named value: that
  #     set reaches every workspace except gcp-guardrails;
  #   - it is tfc-admin (org-admin TFE_TOKEN) or a saas-* workspace (account-wide
  #     Supabase/Vercel tokens), whose secrets are set by hand.
  # The broad platform team gets runs = read, never plan, on every project that
  # holds one; the workspace gets no workspace-level write and no speculative
  # plans (unless enable_speculative_on_secret_bearing).
  # Marking a variable sensitive is the contract; the name pattern is defence
  # in depth for a secret that was not marked.
  secret_variable_key_pattern = "(?i)(^|_)(TOKEN|SECRET|SECRET_KEY|SERVICE_ROLE_KEY|PASSWORD|PASSWD|PASSPHRASE|PRIVATE_KEY|API_KEY|ACCESS_KEY|CREDENTIALS)$"
  common_set_is_secret = anytrue([
    for k, v in var.common_workspace_variables : v.sensitive || can(regex(local.secret_variable_key_pattern, k))
  ])
  # The bridge flag fails closed: a present key counts as on unless its value
  # is an explicit false ("false", "0" or "" after trimming spaces and quotes,
  # any case). "1", "!false" or "1 == 1" (HCL) all count as on.
  saas_bridge_keys       = ["enable_saas_secret_bridge", "TF_VAR_enable_saas_secret_bridge"]
  saas_bridge_off_values = ["false", "0", ""]
  secret_bearing_workspaces = toset(concat(
    [
      for ws, vars in local.workspace_vars : ws
      if anytrue([for k, v in vars : v.sensitive || can(regex(local.secret_variable_key_pattern, k))])
    ],
    [
      for ws, vars in local.workspace_vars : ws
      if anytrue([
        for k in local.saas_bridge_keys : contains(keys(vars), k) &&
        !contains(local.saas_bridge_off_values, try(lower(trim(vars[k].value, " \t\r\n\"'")), "unparsed"))
      ])
    ],
    local.common_set_is_secret ? [for ws in local.workspace_names : ws if !contains(local.guardrails_workspaces, ws)] : [],
    local.saas_workspace_names,
    var.manage_tfc_admin_workspace ? [var.tfc_admin_workspace_name] : [],
  ))
  secret_bearing_workloads_in_control_plane = sort([
    for ws in local.secret_bearing_workspaces : ws
    if contains(["gcp", "aws"], local.workspaces[ws].cloud) && !local.is_control_plane[ws] &&
    contains(local.control_plane_projects, local.workspace_project_key[ws])
  ])
  secret_bearing_projects = setunion(
    local.tfc_admin_only_projects,
    local.saas_projects,
    toset([
      for ws in local.secret_bearing_workspaces : local.workspace_project_key[ws]
      if contains(keys(local.workspace_project_key), ws) && contains(local.shared_access_projects, local.workspace_project_key[ws])
    ]),
  )

  # Production gcp-/aws-workload-<env> workspaces this root manages, and the
  # projects holding them: <cloud> (one project per cloud) or
  # <cloud>-workloads (split_workload_projects). Those projects get the
  # control-plane treatment.
  managed_production_workloads = setintersection(local.production_workloads, local.workspace_names)
  production_workload_projects = toset([
    for k in local.managed_production_workloads : local.workspace_project_key[k]
    if contains(local.project_keys, local.workspace_project_key[k])
  ])
  # Secret-bearing projects whose runs the control-plane approvers team
  # confirms: not the tfc-admin project (the tfc-admin team confirms there) and
  # not a saas project that has saas_approvers_team_id.
  control_plane_approved_secret_projects = setsubtract(
    local.secret_bearing_projects,
    setunion(local.tfc_admin_only_projects, setsubtract(local.saas_projects, local.control_plane_approved_saas_projects)),
  )
  platform_custom_projects = setunion(local.control_plane_projects, local.saas_projects, local.production_workload_projects, local.secret_bearing_projects)
  approver_projects = setunion(
    setsubtract(local.control_plane_projects, local.tfc_admin_only_projects),
    local.control_plane_approved_saas_projects,
    local.production_workload_projects,
    local.control_plane_approved_secret_projects,
  )

  team_project_access = merge(
    var.platform_team_id == null ? {} : {
      for p in local.shared_access_projects : "${p}/platform" => {
        project = p
        team_id = var.platform_team_id
        access  = contains(local.platform_custom_projects, p) ? "custom" : "write"
        custom = contains(local.platform_custom_projects, p) ? (
          contains(local.saas_projects, p) ? local.platform_secret_state_access : (
            contains(local.secret_bearing_projects, p) ? merge(local.platform_custom_access, { runs = "read" }) : local.platform_custom_access
          )
        ) : null
      }
    },
    var.control_plane_approvers_team_id == null ? {} : {
      for p in local.approver_projects : "${p}/approvers" => {
        project = p
        team_id = var.control_plane_approvers_team_id
        access  = "custom"
        custom  = local.approvers_custom_access
      }
    },
    var.saas_approvers_team_id == null ? {} : {
      for p in local.saas_projects : "${p}/saas-approvers" => {
        project = p
        team_id = var.saas_approvers_team_id
        access  = "custom"
        custom  = local.approvers_custom_access
      }
    },
    {
      for pair in setproduct(tolist(local.shared_access_projects), var.viewer_team_ids) :
      "${pair[0]}/${pair[1]}" => {
        project = pair[0]
        team_id = pair[1]
        access  = contains(local.saas_projects, pair[0]) ? "custom" : "read"
        custom  = contains(local.saas_projects, pair[0]) ? local.viewer_secret_state_access : null
      }
    },
    var.security_team_id == null || !local.guardrails_project ? {} : {
      "guardrails/security" = { project = "guardrails", team_id = var.security_team_id, access = "custom", custom = local.security_custom_access }
    },
    var.guardrails_release_reader_team_id == null || !local.guardrails_project ? {} : {
      "guardrails/release-reader" = { project = "guardrails", team_id = var.guardrails_release_reader_team_id, access = "custom", custom = local.release_reader_custom_access }
    },
    var.state_backup_team_id == null ? {} : {
      for p in local.shared_access_projects : "${p}/state-backup" => {
        project = p
        team_id = var.state_backup_team_id
        access  = "custom"
        custom  = local.state_backup_custom_access
      } if var.enable_saas_state_backup || !contains(local.saas_projects, p)
    },
    {
      for p in local.drift_projects : "${p}/drift" => {
        project = p
        team_id = var.drift_team_id
        access  = "custom"
        custom  = local.drift_custom_access
      }
    },
  )

  # A refresh-only plan is still a plan: it runs with the workspace's
  # variables. The drift team gets no secret-bearing project (tfc-admin, saas,
  # a project with a static secret) and no guardrails project. There HCP
  # health assessments (enable_health_assessments) are the only drift check.
  drift_projects = var.drift_team_id == null ? toset([]) : setsubtract(local.shared_access_projects, local.secret_bearing_projects)
  drift_workspaces = sort([
    for ws, p in local.workspace_project_key : ws if contains(local.drift_projects, p)
  ])

  # Non-production gcp/aws workload workspaces that share a project with the
  # control plane, with a production workload or with a secret-bearing
  # workspace. A secret-bearing workspace never gets this grant: the saas
  # project and every secret-bearing workload keep platform runs = read.
  platform_workspace_write = var.platform_team_id == null ? toset([]) : toset([
    for k, p in local.workspace_project_key : k
    if !local.is_control_plane[k] && !contains(local.managed_production_workloads, k) &&
    !contains(local.secret_bearing_workspaces, k) &&
    contains(["gcp", "aws"], local.workspaces[k].cloud) &&
    contains(setunion(local.control_plane_projects, local.production_workload_projects, local.secret_bearing_projects), p)
  ])

  # ── Speculative plans ──────────────────────────────────────────
  speculative_disabled = setunion(
    toset(var.speculative_disabled_workspaces),
    toset(local.guardrails_workspaces),
    var.disable_speculative_on_production ? local.production_workloads : toset([]),
    var.disable_speculative_on_saas ? toset(local.saas_workspace_names) : toset([]),
    # Secret-bearing workspaces; saas-* keep their own switch above.
    var.enable_speculative_on_secret_bearing ? toset([]) : setsubtract(local.secret_bearing_workspaces, toset(local.saas_workspace_names)),
  )

  # Every input keyed by workspace name must name a managed workspace of the
  # right cloud (a typo would otherwise silently do nothing).
  unknown_workspace_keys = setsubtract(
    toset(concat(
      keys(var.workspace_variables),
      keys(local.file_workspace_variables),
      keys(var.extra_remote_state_consumers),
      flatten(values(var.extra_remote_state_consumers)),
    )),
    local.workspace_names,
  )
  wrong_cloud_credential_keys = concat(
    [for k in concat(keys(var.gcp_plan_service_accounts), keys(var.gcp_apply_service_accounts)) : k if try(local.workspaces[k].cloud, "") != "gcp"],
    [for k in concat(keys(var.aws_plan_role_arns), keys(var.aws_apply_role_arns), keys(var.aws_workspace_account_keys)) : k if try(local.workspaces[k].cloud, "") != "aws"],
    [for k in keys(var.aws_alias_role_arns) : k if !contains(keys(local.aws_alias_roles), k)],
    [for k in keys(var.aws_workspace_account_keys) : k if contains(local.aws_management_workspaces, k)],
  )
  unknown_alias_keys = flatten([
    for ws, aliases in var.aws_alias_role_arns : [for a in keys(aliases) : "${ws}.${a}" if !contains(lookup(local.aws_alias_accounts, ws, []), a)]
  ])
}

# Fail the plan on inputs that reference workspaces this root does not manage.
resource "terraform_data" "input_contract" {
  lifecycle {
    precondition {
      condition     = !var.manage_tfc_admin_workspace || !contains(keys(local.catalog_roots), var.tfc_admin_workspace_name)
      error_message = "tfc_admin_workspace_name (${var.tfc_admin_workspace_name}) collides with a workspace catalog key (${join(", ", sort(keys(local.catalog_roots)))}): a self-managed tfc-admin workspace needs its own name."
    }
    precondition {
      condition     = length(setsubtract(toset([for k, e in local.catalog_entries : e.dir]), toset(keys(local.root_trigger_dirs)))) == 0
      error_message = "Catalog roots without a root_trigger_dirs entry (their workspaces would trigger on no module change): ${join(", ", sort(tolist(setsubtract(toset([for k, e in local.catalog_entries : e.dir]), toset(keys(local.root_trigger_dirs))))))}."
    }
    precondition {
      condition     = length(local.unknown_workspace_keys) == 0
      error_message = "workspace_variables / extra_remote_state_consumers reference unmanaged workspaces: ${join(", ", sort(tolist(local.unknown_workspace_keys)))}."
    }
    precondition {
      condition     = length(local.wrong_cloud_credential_keys) == 0
      error_message = "Dynamic-credential maps reference workspaces that are not managed workspaces of that cloud: ${join(", ", distinct(local.wrong_cloud_credential_keys))}."
    }
    precondition {
      condition     = length(var.gcp_plan_service_accounts) + length(var.gcp_apply_service_accounts) == 0 || local.gcp_workload_provider_name != "unset"
      error_message = "gcp_plan_service_accounts/gcp_apply_service_accounts need gcp_workload_provider_name (or gcp_bootstrap_outputs_from_tfc = true)."
    }
    precondition {
      condition     = length(local.unknown_alias_keys) == 0
      error_message = "aws_alias_role_arns names aliases the root does not declare (${join("; ", [for ws, a in local.aws_alias_accounts : "${ws}: ${join(", ", a)}"])}): ${join(", ", local.unknown_alias_keys)}."
    }
    precondition {
      condition     = length(local.aws_incomplete_multi_account) == 0
      error_message = "Multi-account AWS workspaces have default credentials but not every alias role (TFC_AWS_*_<alias>): ${join(", ", local.aws_incomplete_multi_account)}. Supply aws_alias_role_arns or aws_organization_outputs_from_tfc, or remove the workspace's explicit aws_plan_role_arns / aws_apply_role_arns."
    }
    precondition {
      condition     = length(local.file_reserved_entries) == 0
      error_message = "workspace_variables_file sets reserved environment variables: ${join(", ", local.file_reserved_entries)}. Dynamic-credential (TFC_*), CLI (TF_CLI_ARGS*, TF_CLI_CONFIG_FILE, TERRAFORM_CONFIG, TF_TOKEN_*, TF_*), TFE_*, provider-auth, loader and interpreter (LD_*, DYLD_*, NODE_*, PYTHON*, GIT_*, BASH_ENV, ENV, PATH), proxy and CA (SSL_CERT_*, NODE_EXTRA_CA_CERTS) env vars never come from the committed file: tfc-admin derives the credential ones, and workspace_variables may set the credential, CLI-argument, proxy and CA ones (not the loader or interpreter ones)."
    }
    precondition {
      condition     = length(local.workspace_variables_exec_entries) == 0
      error_message = "workspace_variables sets environment variables that make the run execute other code: ${join(", ", local.workspace_variables_exec_entries)}. TERRAFORM_CONFIG, TF_CLI_CONFIG_FILE, LD_*, DYLD_*, NODE_OPTIONS, NODE_PATH, GIT_*, BASH_ENV, ENV, PYTHON* and PATH are refused on every workspace."
    }
    precondition {
      condition     = length(local.file_sensitive_entries) == 0
      error_message = "workspace_variables_file must not hold sensitive values (it is committed): ${join(", ", local.file_sensitive_entries)}. Set secrets via workspace_variables (write-only) instead."
    }
    precondition {
      condition     = var.control_plane_approvers_team_id == null || var.control_plane_approvers_team_id != var.platform_team_id
      error_message = "control_plane_approvers_team_id must differ from platform_team_id: the approvers team exists so the people who change the control plane are not the ones who approve its apply."
    }
    precondition {
      condition     = var.security_team_id == null || (var.security_team_id != var.platform_team_id && var.security_team_id != var.control_plane_approvers_team_id)
      error_message = "security_team_id must differ from platform_team_id and control_plane_approvers_team_id: the security team alone applies gcp-guardrails, which contains the platform's own automation identity."
    }
    precondition {
      condition = length(setintersection(
        toset(values(var.saas_outputs_reader_team_ids)),
        toset(concat(compact([var.platform_team_id, var.control_plane_approvers_team_id, var.security_team_id, var.tfc_admin_team_id]), var.viewer_team_ids)),
      )) == 0
      error_message = "saas_outputs_reader_team_ids values must be dedicated teams (not platform_team_id, control_plane_approvers_team_id, security_team_id, tfc_admin_team_id or a viewer_team_ids entry): each token sits on workload workspaces, so it must carry read-outputs on one saas-* workspace and nothing else."
    }
    precondition {
      condition = var.state_backup_team_id == null || !contains(
        concat(compact([var.platform_team_id, var.control_plane_approvers_team_id, var.security_team_id, var.tfc_admin_team_id]), var.viewer_team_ids, values(var.saas_outputs_reader_team_ids)),
        coalesce(var.state_backup_team_id, "-"),
      )
      error_message = "state_backup_team_id must be a dedicated team (not platform_team_id, control_plane_approvers_team_id, security_team_id, tfc_admin_team_id, a viewer_team_ids entry or a saas_outputs_reader_team_ids value): its token reads every state file, so it must carry nothing else."
    }
    precondition {
      condition = var.saas_approvers_team_id == null || !contains(
        concat(compact([var.platform_team_id, var.control_plane_approvers_team_id, var.security_team_id, var.tfc_admin_team_id, var.state_backup_team_id]), var.viewer_team_ids, values(var.saas_outputs_reader_team_ids)),
        coalesce(var.saas_approvers_team_id, "-"),
      )
      error_message = "saas_approvers_team_id must be a dedicated team (not platform_team_id, control_plane_approvers_team_id, security_team_id, tfc_admin_team_id, state_backup_team_id, a viewer_team_ids entry or a saas_outputs_reader_team_ids value): its members can read the account-wide SaaS tokens through a plan."
    }
    precondition {
      condition = var.drift_team_id == null || !contains(
        concat(compact([var.platform_team_id, var.control_plane_approvers_team_id, var.security_team_id, var.tfc_admin_team_id, var.state_backup_team_id, var.saas_approvers_team_id]), var.viewer_team_ids, values(var.saas_outputs_reader_team_ids)),
        coalesce(var.drift_team_id, "-"),
      )
      error_message = "drift_team_id must be a dedicated team (not platform_team_id, control_plane_approvers_team_id, security_team_id, tfc_admin_team_id, state_backup_team_id, saas_approvers_team_id, a viewer_team_ids entry or a saas_outputs_reader_team_ids value): its token sits in GitHub (environment tfc-drift) and may queue plans, so it must carry nothing else."
    }
    precondition {
      condition = var.guardrails_release_reader_team_id == null || !contains(
        concat(compact([var.platform_team_id, var.control_plane_approvers_team_id, var.security_team_id, var.tfc_admin_team_id, var.state_backup_team_id, var.saas_approvers_team_id, var.drift_team_id]), var.viewer_team_ids, values(var.saas_outputs_reader_team_ids)),
        coalesce(var.guardrails_release_reader_team_id, "-"),
      )
      error_message = "guardrails_release_reader_team_id must be a dedicated team (not platform_team_id, control_plane_approvers_team_id, security_team_id, tfc_admin_team_id, state_backup_team_id, saas_approvers_team_id, drift_team_id, a viewer_team_ids entry or a saas_outputs_reader_team_ids value): its token sits in GitHub (environment tfc-readonly) and must carry runs = read on the guardrails project and nothing else."
    }
    precondition {
      condition     = length(distinct(values(var.saas_outputs_reader_team_ids))) == length(var.saas_outputs_reader_team_ids)
      error_message = "saas_outputs_reader_team_ids must map each saas-* workspace to its own team: a shared team would let a non-production workload's token read production saas outputs."
    }
    precondition {
      condition     = length(setsubtract(toset(keys(var.saas_outputs_reader_team_ids)), toset(local.saas_workspace_names))) == 0
      error_message = "saas_outputs_reader_team_ids names workspaces that are not managed saas-* workspaces: ${join(", ", sort(tolist(setsubtract(toset(keys(var.saas_outputs_reader_team_ids)), toset(local.saas_workspace_names)))))}."
    }
    precondition {
      condition     = local.gcp_project_prefix == null || can(regex("^[a-z][a-z0-9-]{0,9}$", coalesce(local.gcp_project_prefix, "a")))
      error_message = "The GCP prefix (gcp_project_prefix, else org.prefix in config/landing-zone.yaml) must start with a lowercase letter, contain only lowercase letters, digits and hyphens, and be 10 characters or fewer (the gcp-bootstrap project_prefix rule)."
    }
    precondition {
      condition     = length(local.gcp_workload_account_ids_too_long) == 0
      error_message = "GCP service-account IDs are at most 30 characters, so <prefix>-wl-<env>-apply must fit (prefix from gcp_project_prefix or org.prefix): ${join(", ", local.gcp_workload_account_ids_too_long)}. Shorten the gcp.environments key or the prefix."
    }
    precondition {
      condition     = length(local.cidr_overlaps) == 0 && length(local.cidr_outside_aws_top) == 0 && length(local.cidr_outside_aws_pool) == 0 && length(local.cidr_pool_issues) == 0
      error_message = "config/landing-zone.yaml address plan conflicts (docs/architecture/cidr-plan.md: GCP 10.0.0.0/12, AWS 10.64.0.0/10, one regional pool per region): ${join("; ", concat(local.cidr_overlaps, local.cidr_outside_aws_top, local.cidr_outside_aws_pool, local.cidr_pool_issues))}. Give every aws.workload_environments entry its own vpc_cidr inside aws.network.regional_cidrs.<org.regions.aws> or one of its aws.network.regional_additional_cidrs, and keep aws.network.vpn.onprem_cidrs clear of every cloud range."
    }
    precondition {
      condition     = length(local.aws_workloads_needing_network) == 0
      error_message = "aws-workload-<env> in hub mode reads the aws-network workspace's state, but aws.layers (aws_layers) has no network layer: ${join(", ", local.aws_workloads_needing_network)}. Add network to aws.layers, set aws.contracts.network, or drop the enable_network_hub override (tfc-admin sets enable_network_hub = false without the network layer)."
    }
    precondition {
      condition     = length(local.file_bad_categories) == 0
      error_message = "workspace_variables_file categories must be terraform or env: ${join(", ", local.file_bad_categories)}."
    }
    precondition {
      condition     = length(local.file_security_only_entries) == 0
      error_message = "workspace_variables_file sets variables on security-only workspaces: ${join(", ", local.file_security_only_entries)}. Their inputs come from their own security-owned root (e.g. envs/gcp/guardrails/guardrails.auto.tfvars) or the security team's workspace_variables, never from the platform-editable committed file."
    }
  }
}

# ── Upstream outputs (second pass of the bootstrap) ─────────────────────────
data "tfe_outputs" "gcp_bootstrap" {
  count        = var.gcp_bootstrap_outputs_from_tfc ? 1 : 0
  organization = local.tfc_organization
  workspace    = "gcp-bootstrap"

  # Fail instead of silently dropping the TFC_* dynamic-credential variables:
  # the reads in locals use try(), so a renamed or missing output would
  # otherwise leave every workspace this upstream feeds without credentials.
  lifecycle {
    postcondition {
      condition     = length(setsubtract(["tfc_workload_provider_name", "tfc_plan_service_accounts", "tfc_apply_service_accounts"], keys(try(self.nonsensitive_values.contract, self.nonsensitive_values, {})))) == 0
      error_message = "gcp_bootstrap_outputs_from_tfc = true but the gcp-bootstrap outputs lack ${join(", ", sort(tolist(setsubtract(["tfc_workload_provider_name", "tfc_plan_service_accounts", "tfc_apply_service_accounts"], keys(try(self.nonsensitive_values.contract, self.nonsensitive_values, {}))))))}. Apply gcp-bootstrap first. If it has applied, its contract output changed (scripts/check-contracts.sh). Without these keys no gcp-* workspace gets TFC_GCP_* dynamic credentials."
    }
  }
}

data "tfe_outputs" "aws_organization" {
  count        = var.aws_organization_outputs_from_tfc ? 1 : 0
  organization = local.tfc_organization
  workspace    = "aws-organization"

  # Fail instead of silently dropping the TFC_* dynamic-credential variables:
  # the reads in locals use try(), so a renamed or missing output would
  # otherwise leave every workspace this upstream feeds without credentials.
  lifecycle {
    postcondition {
      condition     = length(setsubtract(["tfc_plan_role_arns", "tfc_apply_role_arns", "tfc_workspace_bindings"], keys(try(self.nonsensitive_values.contract, self.nonsensitive_values, {})))) == 0
      error_message = "aws_organization_outputs_from_tfc = true but the aws-organization outputs lack ${join(", ", sort(tolist(setsubtract(["tfc_plan_role_arns", "tfc_apply_role_arns", "tfc_workspace_bindings"], keys(try(self.nonsensitive_values.contract, self.nonsensitive_values, {}))))))}. Apply aws-organization first. If it has applied, its contract output changed (scripts/check-contracts.sh). Without these keys no aws-* workspace gets TFC_AWS_* dynamic credentials."
    }
  }
}

# The hand-created tfc-admin workspace, looked up only when it is not
# self-managed and must be granted read access to an upstream state, be the
# source of the DAG-root run triggers, or be judged by the policy sets.
data "tfe_workspace" "tfc_admin" {
  count        = (length(local.tfc_admin_reads) > 0 || length(local.tfc_admin_trigger_targets) > 0 || local.enable_policy_sets) && !var.manage_tfc_admin_workspace ? 1 : 0
  name         = var.tfc_admin_workspace_name
  organization = local.tfc_organization
}

# ── Projects + team access ──────────────────────────────────────────────────
resource "tfe_project" "this" {
  for_each = local.project_keys

  organization = local.tfc_organization
  name         = local.project_names[each.key]
  description  = "Landing-zone ${each.key} workspaces (managed by tfc-admin)."
}

resource "tfe_team_project_access" "this" {
  for_each = local.team_project_access

  project_id = tfe_project.this[each.value.project].id
  team_id    = each.value.team_id
  access     = each.value.access

  # Custom grants: no project-settings, team or variable-set management, and no
  # workspace create/delete/move, run tasks or policy overrides.
  dynamic "project_access" {
    for_each = each.value.custom == null ? [] : [each.value.custom]
    content {
      settings      = "read"
      teams         = "none"
      variable_sets = "read"
    }
  }

  dynamic "workspace_access" {
    for_each = each.value.custom == null ? [] : [each.value.custom]
    content {
      runs             = workspace_access.value.runs
      variables        = workspace_access.value.variables
      state_versions   = workspace_access.value.state_versions
      sentinel_mocks   = workspace_access.value.sentinel_mocks
      locking          = workspace_access.value.locking
      create           = false
      delete           = false
      move             = false
      run_tasks        = false
      policy_overrides = false
    }
  }
}

# Platform-team write on non-production workload workspaces that live in a
# project with custom platform access (the control-plane project when there is
# one project per cloud, or a <cloud>-workloads project that also holds a
# production workload); additive to the custom project grant.
resource "tfe_team_access" "platform_workload" {
  for_each = local.platform_workspace_write

  team_id      = var.platform_team_id
  workspace_id = module.workspace[each.key].id
  access       = "write"
}

# SaaS bridge readers: one hand-created team per saas-<name> workspace reads
# that workspace's outputs (state_versions = read-outputs) and nothing else.
# Its team token is the TFE_TOKEN of the workload workspaces that bridge that
# stack (enable_saas_secret_bridge); an owner creates it by hand with an expiry
# (docs/runbooks/saas-bootstrap.md), so it never enters this root's state. One
# team per stack means a token stolen from a non-production workload plan
# cannot read a production stack's outputs.
resource "tfe_team_access" "saas_outputs_reader" {
  for_each = { for ws, team in var.saas_outputs_reader_team_ids : ws => team if contains(local.saas_workspace_names, ws) }

  team_id      = each.value
  workspace_id = module.workspace[each.key].id

  permissions {
    runs              = "read"
    variables         = "none"
    state_versions    = "read-outputs"
    sentinel_mocks    = "none"
    workspace_locking = false
    run_tasks         = false
  }
}

# Explicit apply grant for the team that owns tfc-admin's token. That team's
# token also holds organization-level manage_workspaces, so this is a
# belt-and-braces record of who may confirm tfc-admin's own applies.
resource "tfe_team_access" "tfc_admin" {
  count = var.manage_tfc_admin_workspace && var.tfc_admin_team_id != null ? 1 : 0

  team_id      = var.tfc_admin_team_id
  workspace_id = module.workspace[var.tfc_admin_workspace_name].id
  access       = "write"
}

# ── Shared variable set ─────────────────────────────────────────────────────
# Org-wide values live once in a variable set attached to every managed
# workspace except gcp-guardrails, instead of being copied onto each one. Workspace variables still
# override set values (priority = false).
resource "tfe_variable_set" "common" {
  organization = local.tfc_organization
  name         = "${local.project_name_prefix}common"
  description  = "Values shared by every landing-zone workspace (managed by tfc-admin)."
}

resource "tfe_variable" "common" {
  for_each = merge(
    { tfc_organization = { value = local.tfc_organization, category = "terraform", hcl = false, sensitive = false, description = "TFC organization (remote-state reads).", version = 1 } },
    var.common_workspace_variables,
  )

  variable_set_id = tfe_variable_set.common.id
  key             = each.key
  # Sensitive values are written write-only (never stored in tfc-admin state).
  value            = each.value.sensitive ? null : each.value.value
  value_wo         = each.value.sensitive ? each.value.value : null
  value_wo_version = each.value.sensitive ? each.value.version : null
  category         = each.value.category
  hcl              = each.value.hcl
  sensitive        = each.value.sensitive
  description      = each.value.description
}

# ── Workspaces ──────────────────────────────────────────────────────────────
module "workspace" {
  source   = "../../modules/tfc/workspace"
  for_each = local.workspaces

  name              = each.key
  organization      = local.tfc_organization
  description       = each.value.desc
  working_directory = each.value.dir
  # tier:production marks the production workloads for the TFC-layer policy
  # (policies/opa-destructive/tfc_admin_guard.rego: no auto-apply there).
  tag_names         = contains(local.managed_production_workloads, each.key) ? concat(each.value.tags, ["tier:production"]) : each.value.tags
  terraform_version = var.terraform_version
  project_id        = var.enable_projects ? tfe_project.this[local.workspace_project_key[each.key]].id : null

  vcs_repo              = local.vcs_repo
  file_triggers_enabled = true
  # Own dir + the module trees this root composes + this estate's config files.
  trigger_patterns = concat(
    ["${each.value.dir}/**"],
    [for d in lookup(local.root_trigger_dirs, each.value.dir, []) : "${d}/**"],
    local.estate_config_trigger_patterns,
  )

  # Control plane and production workloads: no automatic speculative PR plans
  # (a PR's code would run as the plan identity); no UI destroy plans on the
  # control plane. auto_apply is false unless auto_apply_on_merge (the sandbox
  # estate); the never_auto_apply_workspaces (gcp-guardrails, tfc-admin) stay
  # false under it too.
  speculative_enabled = !contains(local.speculative_disabled, each.key)
  allow_destroy_plan  = !local.is_control_plane[each.key]
  # Non-production workloads also auto-apply run-trigger runs (an upstream
  # apply carries down to them) and queue a run at creation, so a new non-prod
  # environment builds itself; production and shared workspaces still wait for
  # a human confirmation.
  auto_apply             = var.auto_apply_on_merge && !contains(local.never_auto_apply_workspaces, each.key)
  auto_apply_run_trigger = (var.auto_apply_on_merge || contains(local.nonprod_auto_apply_workloads, each.key)) && !contains(local.never_auto_apply_workspaces, each.key)
  queue_all_runs         = contains(local.nonprod_auto_apply_workloads, each.key)

  assessments_enabled = var.enable_health_assessments

  # Settings (execution mode + remote-state consumers) are declared below so a
  # workspace can list its sibling workspaces as consumers without a cycle.
  manage_settings = false

  variables = local.workspace_vars[each.key]
  # gcp-guardrails gets no shared variable set: the platform-controlled common
  # set could otherwise inject inputs (e.g. containment_exempt_principals) into
  # the security team's workspace. The root needs none of its values
  # (tfc_organization is unused there: it reads no remote state).
  variable_set_ids = contains(local.guardrails_workspaces, each.key) ? {} : { common = tfe_variable_set.common.id }

  # Control-plane and bootstrap workspaces alert on failed runs;
  # workload workspaces use the separate workload channel (both default empty).
  notifications = local.is_control_plane[each.key] ? local.control_plane_notifications : local.workload_notifications
}

# Remote-state sharing: global_remote_state is false on every workspace and only
# the explicit consumer graph (local.consumer_ids) may read a state file.
resource "tfe_workspace_settings" "this" {
  for_each = local.workspaces

  workspace_id              = module.workspace[each.key].id
  execution_mode            = local.execution_modes[each.key]
  agent_pool_id             = local.execution_modes[each.key] == "agent" ? var.agent_pool_id : null
  global_remote_state       = false
  remote_state_consumer_ids = local.consumer_ids[each.key]
}

# Without a security team the guardrails project has no team grant (only
# organization owners can run gcp-guardrails); without projects there is no
# separate project at all.
check "guardrails_project_has_security_team" {
  assert {
    condition     = length(local.guardrails_workspaces) == 0 || (local.guardrails_project && var.security_team_id != null)
    error_message = "gcp-guardrails is managed but ${local.guardrails_project ? "security_team_id is null: no team can run it (organization owners only). Create a security team and set security_team_id." : "enable_projects = false: it shares the default project instead of a security-only one. Set enable_projects = true and security_team_id."}"
  }
}

# With one project per cloud, a secret-bearing workload shares its project with
# the control plane, so the platform team can no longer queue control-plane
# plans either. split_workload_projects = true keeps them apart. A sensitive or
# secret-named value in the shared variable set reaches every control-plane
# workspace, so it has the same effect in both modes.
check "secret_bearing_control_plane_project" {
  assert {
    condition     = length(local.secret_bearing_workloads_in_control_plane) == 0
    error_message = "Secret-bearing workloads (a sensitive or secret-named variable, or enable_saas_secret_bridge) share a TFC project with control-plane workspaces: ${join(", ", local.secret_bearing_workloads_in_control_plane)}. The platform team gets runs = read on that whole project, control plane included. Set split_workload_projects = true (org.tfc.split_workload_projects) to keep control-plane plans."
  }
  assert {
    condition     = !local.common_set_is_secret
    error_message = "common_workspace_variables carries a sensitive or secret-named value, and the shared variable set reaches every workspace except gcp-guardrails: every project is secret-bearing and the platform team gets runs = read everywhere. Set that value on the workspaces that need it (workspace_variables) instead."
  }
}

# Without an approvers team, only organization owners can confirm runs on a
# secret-bearing project (the platform team has runs = read there). The
# tfc-admin project is left out: the tfc-admin team confirms its runs. So is a
# saas project when saas_approvers_team_id confirms its runs.
check "secret_bearing_projects_have_approvers" {
  assert {
    condition     = var.platform_team_id == null || var.control_plane_approvers_team_id != null || length(local.control_plane_approved_secret_projects) == 0
    error_message = "control_plane_approvers_team_id is null while these projects are secret-bearing: ${join(", ", sort(tolist(local.control_plane_approved_secret_projects)))}. The platform team has runs = read there, so only organization owners can queue and confirm their runs. Set control_plane_approvers_team_id."
  }
}

# Whoever confirms a saas-* apply can also queue a plan, and a plan can read
# the account-wide SUPABASE_ACCESS_TOKEN and VERCEL_API_TOKEN. Without a
# dedicated saas approvers team the whole control-plane approvers team holds
# that exposure.
check "saas_approvers_dedicated" {
  assert {
    condition     = length(local.saas_projects) == 0 || var.saas_approvers_team_id != null || var.control_plane_approvers_team_id == null
    error_message = "saas-* applies are confirmed by control_plane_approvers_team_id. A confirmer can also queue a plan and read SUPABASE_ACCESS_TOKEN and VERCEL_API_TOKEN. Set saas_approvers_team_id to a smaller, dedicated team."
  }
}

# Adopt the hand-created tfc-admin workspace instead of creating a duplicate.
# An unmanaged tfc-admin workspace keeps TFC's default speculative_enabled =
# true. With a VCS connection that hands every PR a plan that can read the
# org-admin TFE_TOKEN, so warn on every plan until it is adopted.
check "tfc_admin_workspace_hardened" {
  assert {
    condition     = var.manage_tfc_admin_workspace || local.vcs_repo == null
    error_message = "manage_tfc_admin_workspace = false while vcs_repo is set: the hand-created tfc-admin workspace keeps speculative PR plans ON, so a pull request's plan can read its org-admin TFE_TOKEN. Set manage_tfc_admin_workspace = true, or disable speculative plans on it by hand."
  }
}

import {
  for_each = var.manage_tfc_admin_workspace && var.import_tfc_admin_workspace ? toset([var.tfc_admin_workspace_name]) : toset([])
  to       = module.workspace[each.key].tfe_workspace.this
  id       = "${local.tfc_organization}/${each.key}"
}

# ── OPA policy sets (both sourced from this repo via VCS) ──────────────────
# Two sets, attached to every managed workspace:
#   - <prefix>opa-guardrails (policies/opa): enforcement per policy in its
#     policies.hcl, 13 mandatory (public exposure, identity, encryption,
#     plan-time code execution, labels) + 3 advisory. NOT overridable by default (policy_set_overridable = false), so
#     a mandatory failure is a hard stop no "Manage Policy Overrides" user can
#     wave through.
#   - <prefix>destructive-change-guard (policies/opa-destructive): the
#     mandatory destroy_guard, which stops any delete or replace of a stateful
#     resource, and the mandatory tfc_admin_guard, which stops a plan that
#     detaches a policy set, turns on auto-apply for a production or
#     control-plane workspace, widens team access, moves runs to local or
#     agent execution, rewires a protected workspace (VCS, working directory,
#     project) or writes a TFC_* / TF_CLI_ARGS* / code-execution env var,
#     and the PREVIEW tfc_vcs_run_only, which stops a control-plane or
#     production apply of code that did not come from VCS.
#     Always overridable: an
#     intended change is overridden on the run by the security team. An owner creates that team by hand (its ID is
#     security_team_id) and grants it Manage Policy Overrides in the HCP UI;
#     this root creates no teams and sets no organization access, so it keeps
#     running on a non-owner token.
# A VCS policy set reads the policies.hcl in its own policies_path, hence the
# separate directory (with its own copy of lib_helpers.rego).
# enable_policy_sets = null turns both on when vcs_repo is set and the plan
# (tfc_plan / org.tfc.plan) is standard or premium.
locals {
  policy_sets = {
    opa = {
      name        = "${local.project_name_prefix}opa-guardrails"
      description = "Landing-zone OPA guardrails from policies/opa (mixed mandatory/advisory; see policies.hcl)."
      path        = "policies/opa"
      overridable = var.policy_set_overridable
    }
    destructive = {
      name        = "${local.project_name_prefix}destructive-change-guard"
      description = "Mandatory guards from policies/opa-destructive: stop deletes and replaces of stateful resources, policy-set detachment, auto-apply on production or control-plane workspaces and widened team access unless the security team overrides."
      path        = "policies/opa-destructive"
      overridable = true
    }
  }
  # Every managed workspace plus tfc-admin itself, also when it is not
  # self-managed: the TFC-layer rules in the destructive set judge tfc-admin's
  # own plans (detaching a policy set, auto-apply, widened team access).
  policy_set_workspace_ids = concat(
    [for k in sort(keys(module.workspace)) : module.workspace[k].id],
    var.manage_tfc_admin_workspace || !local.enable_policy_sets ? [] : [data.tfe_workspace.tfc_admin[0].id],
  )
}

resource "tfe_policy_set" "opa" {
  count = local.enable_policy_sets ? 1 : 0

  organization        = local.tfc_organization
  name                = local.policy_sets.opa.name
  description         = local.policy_sets.opa.description
  kind                = "opa"
  overridable         = local.policy_sets.opa.overridable
  policy_tool_version = var.opa_version
  policies_path       = local.policy_sets.opa.path
  workspace_ids       = local.policy_set_workspace_ids

  dynamic "vcs_repo" {
    for_each = local.vcs_repo == null ? [] : [local.vcs_repo]
    content {
      identifier                 = vcs_repo.value.identifier
      branch                     = vcs_repo.value.branch
      oauth_token_id             = vcs_repo.value.oauth_token_id
      github_app_installation_id = vcs_repo.value.github_app_installation_id
    }
  }

  lifecycle {
    precondition {
      condition     = local.vcs_repo != null
      error_message = "enable_policy_sets = true requires vcs_repo (or org.tfc.vcs_repo in config/landing-zone.yaml): the policy sets are sourced from policies/opa and policies/opa-destructive in the repo."
    }
  }
}

resource "tfe_policy_set" "destructive" {
  count = local.enable_policy_sets ? 1 : 0

  organization        = local.tfc_organization
  name                = local.policy_sets.destructive.name
  description         = local.policy_sets.destructive.description
  kind                = "opa"
  overridable         = local.policy_sets.destructive.overridable
  policy_tool_version = var.opa_version
  policies_path       = local.policy_sets.destructive.path
  workspace_ids       = local.policy_set_workspace_ids

  dynamic "vcs_repo" {
    for_each = local.vcs_repo == null ? [] : [local.vcs_repo]
    content {
      identifier                 = vcs_repo.value.identifier
      branch                     = vcs_repo.value.branch
      oauth_token_id             = vcs_repo.value.oauth_token_id
      github_app_installation_id = vcs_repo.value.github_app_installation_id
    }
  }

  lifecycle {
    precondition {
      condition     = local.vcs_repo != null
      error_message = "enable_policy_sets = true requires vcs_repo (or org.tfc.vcs_repo in config/landing-zone.yaml): the policy sets are sourced from policies/opa and policies/opa-destructive in the repo."
    }
  }
}

# Without the policy sets nothing stops a plan that deletes or replaces a
# stateful resource (KMS keys, databases, buckets, accounts, projects). On a
# plan without VCS policy sets, drift-detection.yml is the remaining backstop.
check "destructive_changes_guarded" {
  assert {
    condition     = local.enable_policy_sets || !var.enable_unguarded_destroy_warning
    error_message = "Policy sets are off (${local.vcs_repo == null ? "no vcs_repo / org.tfc.vcs_repo" : "org.tfc.plan / tfc_plan is ${coalesce(local.tfc_plan, "unset")}, not standard or premium"}): destructive changes are unguarded, no destroy_guard stops a delete or replace of a stateful resource. Set vcs_repo and org.tfc.plan, or enable_policy_sets = true on a plan that supports VCS policy sets."
  }
}

# Overrides of the destructive-change guard need a team holding Manage Policy
# Overrides (org-wide; granted by an owner in the HCP UI, never by this root).
check "destructive_override_team" {
  assert {
    condition     = !local.enable_policy_sets || var.security_team_id != null
    error_message = "The destructive-change guard is on but security_team_id is null: only organization owners can override an intended destroy. Create a security team, grant it Manage Policy Overrides in the HCP UI and set security_team_id."
  }
}

# ── gcp-bootstrap: immutable workspace IDs for the WIF bindings ─────────────
# gcp-bootstrap binds each gcp-* workspace's plan/apply SA by workspace ID when
# it knows the ID (by name otherwise, which a production estate rejects). The
# IDs only exist once this root has created the workspaces, so it writes them
# onto gcp-bootstrap here (a separate resource, so the workspace module does not
# depend on its own IDs). The local phase-0 apply runs in local execution mode,
# which ignores workspace variables: use output.gcp_bootstrap_tfvars there.
locals {
  gcp_bootstrap_workspace_ids = {
    for ws, m in module.workspace : ws => m.id if startswith(ws, "gcp-")
  }
  set_gcp_bootstrap_workspace_ids = (
    var.set_gcp_bootstrap_workspace_ids &&
    contains(keys(local.workspaces), "gcp-bootstrap") &&
    !contains(keys(lookup(local.workspace_vars, "gcp-bootstrap", {})), "tfc_workspace_ids")
  )
}

resource "tfe_variable" "gcp_bootstrap_workspace_ids" {
  count = local.set_gcp_bootstrap_workspace_ids ? 1 : 0

  workspace_id = module.workspace["gcp-bootstrap"].id
  key          = "tfc_workspace_ids"
  value        = jsonencode(local.gcp_bootstrap_workspace_ids)
  category     = "terraform"
  hcl          = true
  description  = "TFC workspace name -> immutable ID for every gcp-* workspace (set by tfc-admin), so gcp-bootstrap binds WIF by ID, never by squattable name."
}

# ── Run triggers along the dependency DAG ───────────────────────────────────
# A successful apply upstream queues a run downstream, so a change to
# gcp-projects (say) is followed by a plan of gcp-network-hub and every
# gcp-workload-<env> instead of waiting for someone to remember. Without
# auto_apply_on_merge the triggered run is a plan awaiting confirmation; with
# it, the run applies (auto_apply_run_trigger), except on the
# never_auto_apply_workspaces.
# The edges are the catalog's upstreams: only the direct edges (the DAG's
# transitive reduction), so a workload is queued once per upstream change, not
# once per ancestor.
locals {
  # tfc-admin is the DAG root: its apply (a workspace or environment added in
  # config) queues the catalog entries that list it as an upstream (the two
  # phase-0 roots), which carry it down the DAG. A local-execution workspace
  # cannot run a triggered run, so gcp-bootstrap is a target only once it runs
  # remotely (after the handover).
  tfc_admin_trigger_targets = var.enable_run_triggers ? [
    for ws, w in local.workspaces : ws
    if contains(w.upstreams, var.tfc_admin_workspace_name) && lookup(local.execution_modes, ws, "remote") != "local"
  ] : []
  tfc_admin_trigger_source_id = length(local.tfc_admin_trigger_targets) == 0 ? null : (
    var.manage_tfc_admin_workspace ? module.workspace[var.tfc_admin_workspace_name].id : data.tfe_workspace.tfc_admin[0].id
  )
  run_trigger_pairs = var.enable_run_triggers ? merge(
    { for ws in local.tfc_admin_trigger_targets : "${var.tfc_admin_workspace_name}->${ws}" => { source = var.tfc_admin_workspace_name, downstream = ws } },
    merge([
      for downstream, w in local.workspaces : {
        for src in w.upstreams : "${src}->${downstream}" => { source = src, downstream = downstream }
        if src != var.tfc_admin_workspace_name && contains(keys(local.workspaces), src)
      }
    ]...),
  ) : {}
}

resource "tfe_run_trigger" "dag" {
  for_each = local.run_trigger_pairs

  workspace_id  = module.workspace[each.value.downstream].id
  sourceable_id = each.value.source == var.tfc_admin_workspace_name ? local.tfc_admin_trigger_source_id : module.workspace[each.value.source].id
}

# A derived workload SA email that disagrees with what gcp-bootstrap created
# (prefix drift between org.prefix and gcp-bootstrap's project_prefix, or a
# changed naming scheme) would hand the workspace an identity that does not exist.
check "derived_gcp_service_accounts_match_bootstrap" {
  assert {
    condition     = length(local.derived_gcp_sa_mismatches) == 0
    error_message = "Derived workload SA emails differ from the gcp-bootstrap outputs (derived vs output): ${join("; ", local.derived_gcp_sa_mismatches)}. Align gcp_project_prefix / org.prefix with gcp-bootstrap's project_prefix."
  }
}

# Post-handover (tfc-admin reads gcp-bootstrap's outputs) gcp-bootstrap must run
# remotely: a local-execution workspace cannot run what tfc-admin's run trigger
# queues, and its local applies fire no downstream triggers.
check "gcp_bootstrap_remote_after_handover" {
  assert {
    condition     = !var.gcp_bootstrap_outputs_from_tfc || lookup(local.execution_modes, "gcp-bootstrap", "remote") != "local"
    error_message = "gcp_bootstrap_outputs_from_tfc = true but gcp-bootstrap still runs in local execution mode: set workspace_execution_modes = {} so tfc-admin's run trigger (and the DAG below it) reaches gcp-bootstrap."
  }
}
