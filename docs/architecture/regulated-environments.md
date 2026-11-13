# Regulated environments

An environment that holds regulated data (cardholder data, health records,
financial records) can be marked `compliance_class: regulated` in
`config/landing-zone.yaml`. The class is opt-in and set per environment. The
default is `standard`, and a standard environment's plan does not change.

```yaml
gcp:
  environments:
    prod:
      is_production: true
      compliance_class: regulated
aws:
  workload_environments:
    pci:
      account_key: workload_pci
      is_production: true
      compliance_class: regulated
```

`config/landing-zone.schema.json` accepts `standard` and `regulated`. The roots
that read the key also fail the plan on any other value.

## What regulated turns on

Every guard below fails the plan and names the config key or variable to fix.
A guard does not create or change a resource.

| Control | GCP (`gcp-workload-<env>`) | AWS (`aws-network`, `aws-security`) |
|:--|:--|:--|
| Exfiltration perimeter | The VPC-SC perimeter must be enforced. A dry-run or absent perimeter fails the plan, and `production_vpc_sc_dry_run_waiver` is refused. The perimeter admits the environment's own plan and apply service accounts (`automation_identities` from `gcp-projects`), so enforcement does not block the pipeline. | The hub endpoint policy stays `aws:PrincipalOrgID` until you set `aws.network.vpc_endpoint_policy_mode: org_principals_and_resources` (PREVIEW, see below). A regulated estate without it plans with a warning. |
| Egress inspection | No regulated-only change. As in every production environment, the plan fails unless the private tier egresses through the hub Secure Web Proxy or `production_egress_proxy_waiver` is set (NET-13). A regulated environment accepts that waiver while the proxy is PREVIEW (`docs/known-gaps.md`). | The Network Firewall is on, on every profile. The egress gate is on: the plan fails unless `aws.network.stateful_default_actions` includes `aws:drop_established` and `aws.network.egress_domain_allowlist` is not empty. `aws.network.egress_alert_only_waived`, `enforce_egress_allowlist = false` and `enable_network_firewall = false` are refused. |
| Flow logs | Every flow is sampled (`log_config_flow_sampling = 1`), aggregated at `INTERVAL_5_SEC` (the default), and the export is kept 365 days (`vpc_flow_logs_retention_days`). Lower values fail the plan. | VPC flow logs already record `ALL` traffic to the log-archive bucket (LOG-13). Their retention is the log-archive retention (`aws_overrides.log_archive_retention_days`, else `compliance.audit_log_retention_days`, else 365). `aws-security` fails the plan when it is below 365 days. |
| Edge | Cloud Armor with the OWASP managed rules. `enable_cloud_armor = false` or `enable_owasp_rules = false` fails the plan. | No change. |
| Backups | A Backup and DR vault in the host project with enforced retention (default 35 days) and organization-only access, and a daily plan for every app-service database (BCK-07, PREVIEW). `enable_backup_vault = false` fails the plan. The retention lock is never set by the class. | No change. |
| Audit store | `gcp-organization` fails the plan until the audit bucket is WORM-locked in a separate logging project, or an unexpired `gcp.audit_store_waiver` `{reason, expires}` is set (LOG-03, LOG-04). | No change. |
| Database encryption | Every app-service database must set `database.encryption_key_name` (a CMEK in the instance region) and keep deletion protection on, or the plan fails (DP-05). An existing database without a key is never replaced: the plan fails until you migrate it (`UPGRADING.md`). | No change. |

On GCP the values come from the preset
[`examples/presets/regulated-gcp-workload.yaml`](../../examples/presets/regulated-gcp-workload.yaml),
which `envs/gcp/workload` applies last for a regulated environment. You do not
list it in `presets`. An explicit variable still wins over the preset, and the
guards then fail the plan if the variable weakens a regulated value.

On AWS the hub (Network Firewall, egress gate, endpoints) is shared by every
workload account. One regulated workload environment therefore hardens egress
for every spoke in the estate, and a starter estate gets the Network Firewall
(about USD 577 per month idle at two AZs).

## Prerequisites

- GCP: read the environment's VPC-SC dry-run violation logs and fix them before
  you mark it regulated. Apply `gcp-organization` with scoped access policies
  and `gcp-projects` first, so `environment_config` carries the access policy.
- GCP: apply `gcp-bootstrap`, then `gcp-organization`, then `gcp-projects`
  before the first regulated `gcp-workload-<env>` apply, so the workload SAs
  hold the Backup and DR roles (`roles/backupdr.admin`, `roles/backupdr.viewer`).
- GCP: full flow-log sampling raises the Cloud Logging and BigQuery cost of the
  environment's VPC.
- AWS: list every domain your workloads call in
  `aws.network.egress_domain_allowlist` before you mark an environment
  regulated. Unmatched egress is dropped.

## Resource-organization endpoint policy (PREVIEW)

`aws.network.vpc_endpoint_policy_mode: org_principals_and_resources` adds
`aws:ResourceOrgID` to the hub interface endpoint policy for every service
outside the vpc-endpoints module's `resource_org_exempt_services` (by default
only `kms` among the default services). A call through such an endpoint then
succeeds only when the resource belongs to your organization. It is off by
default for every estate, regulated or not, because it has not been proven in a
sandbox. See [`docs/known-gaps.md`](../known-gaps.md).

## What regulated does not give you

- Cardholder-data segmentation inside an environment. Segment by environment
  (one account or host project per cardholder data environment).
- FIPS endpoints.
- Sovereign partitions (AWS GovCloud, the AWS European Sovereign Cloud,
  Assured Workloads).
- Data-layer controls: data classification tags are not tied to the class.
  Cloud SQL CMEK is required, but the class does not create the key: create a
  key in the instance region (Cloud SQL rejects a multi-region or global key)
  and give the Cloud SQL service agent, and with the vault the Backup and DR
  service agent, access to it
  ([Cloud SQL CMEK](https://docs.cloud.google.com/sql/docs/postgres/cmek)).
  The Backup and DR vault is tied to the class, but its retention lock is
  not: set `gcp.environments.<env>.backup_vault.lock_effective_time` yourself.
- Operating evidence. The guards prove the configuration at plan time. Your
  auditor still needs evidence that the controls operated.

## Framework references

Control matrix rows: NET-11 and BCK-07 in
[`docs/compliance/control-matrix.md`](../compliance/control-matrix.md). The
class is designed against NIST SP 800-53 SC-7, SC-7(5), AC-4 and AU-12, PCI DSS
v4.0.1 requirements 1.3, 1.4 and 10.2, and HIPAA 164.312(e)(1). These are design
mappings, not an assessment.
