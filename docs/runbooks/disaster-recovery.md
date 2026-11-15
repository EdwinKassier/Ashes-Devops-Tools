# Runbook: Disaster recovery and recovery objectives

**When to use:** to state recovery objectives for an auditor or a business
impact analysis, to plan a restore test, or to recover data after a loss.

## What this landing zone can recover, and how fast

The numbers below are **design targets, not measurements**. They come from the
backup schedules and settings in this repository. No restore has run against a
real apply (see [`docs/known-gaps.md`](../known-gaps.md)). After your first
restore drill, replace each target with the value you measured.

The default estate is **single-region**: one primary region per cloud, with no
warm standby. Anything that survives the loss of a region, an account or a
project is an opt-in that the third column of the table names.

- RPO (recovery point objective): the most data you can lose. It follows the
  backup interval.
- RTO (recovery time objective): the time to restore service. It depends on
  resource size and on your own steps, so each value is a planning band to be
  replaced with a measurement.

| Asset | Mechanism and schedule in this repository | RPO design target | RTO design target | Opt-in needed |
|:--|:--|:--|:--|:--|
| AWS data tagged `backup = true` (EBS, RDS, Aurora, S3, DynamoDB, EFS and other types AWS Backup supports) | Org `BACKUP_POLICY` on the Workloads OU: daily at 05:00 UTC, kept 365 days (`retention_days`), one region, into the member-account vault (BCK-03) | Up to 24 hours | Hours, per resource size (planning band: under 1 day) | None. Needs `aws-backup` applied |
| Same data after loss of the workload account | Daily copy in the locked central vault `org-backup-copy-vault` in the backup account, Compliance-mode Vault Lock (BCK-01) | Up to 24 hours plus copy time | Restore into another account (planning band: 1 to 2 days) | `compliance.backup.copy_to_central_vault`. EBS volumes on the `aws/ebs` key cannot be copied across accounts |
| Same data after loss of the home region | Daily copy to the member DR-region vault `<vault_name>-cmk` (BCK-03) | Up to 24 hours plus copy time | Rebuild network and restore in the DR region (planning band: 2 days or more; there is no standby network) | `compliance.backup.dr_region` |
| Aurora cluster, point in time | Native continuous backup, window `backup_retention_period` (default 7 days) in `modules/aws/data/rds-aurora` | Minutes (continuous log backup; the lag is not measured here) | Restore creates a new cluster (planning band: under 4 hours for a small cluster) | None |
| Cloud SQL, point in time | PITR (`enable_point_in_time_recovery`, default on), logs kept `transaction_log_retention_days` (default 7), daily automated backup at 03:00 UTC, stored in the instance region (BCK-04) | Minutes (continuous log archiving; the lag is not measured here) | Clone or restore to a new instance (planning band: under 4 hours for a small instance) | None, when the `cloud-sql` module is used |
| Cloud SQL after loss of the project | Daily plan into the Backup and DR vault in the environment host project and region, minimum retention 35 days by default (BCK-07). Backups are immutable for that time | Up to 24 hours | Restore from the vault (planning band: under 1 day) | `compliance_class: regulated` (required) or `enable_backup_vault` |
| GCP Compute Engine disks | Daily snapshot schedule at 04:00 UTC, kept 30 days (BCK-05). Only disks you attach to the policy are covered | Up to 24 hours | Hours (planning band: under 1 day) | Attach disks to the policy |
| Terraform state | `state-backup.yml` copies each workspace's current state daily at 05:30 UTC to write-once buckets. HCP Terraform also keeps every state version | Up to 24 hours | Under 1 hour per workspace once access is regained | Repository variables ([`state-backup.md`](state-backup.md)) |
| Landing-zone configuration and code | Git history plus HCP Terraform workspaces | Last commit | Re-apply time per root, in the order of [`bootstrap.md`](bootstrap.md) and [`aws-bootstrap.md`](aws-bootstrap.md) | None |
| Audit logs | GCP: aggregated sink to a versioned CMEK bucket, WORM lock optional (LOG-02, LOG-03). AWS: CloudTrail into an Object Lock bucket in the log-archive account (LOG-07, LOG-08) | No scheduled gap. Delivery lag is not measured here | Not applicable: read in place | WORM lock on GCP: `enable_audit_bucket_lock` |

What each row does not give you: a hot or warm standby, automatic failover, or a
tested restore. The `aws-backup` restore-testing plan (BCK-02) proves that single
recovery points restore. It does not prove that an environment comes back.

## Not covered (decide and record)

- No warm standby region. No multi-region network or DNS failover. GCP
  `additional_regions` adds subnets only, and workload placement stays in the
  primary region ([`known-gaps.md`](../known-gaps.md)).
- No Aurora Global Database and no Cloud SQL cross-region replica. The Cloud SQL
  `backup_location` input can place backups in another region or a
  multi-region. That is an explicit choice and it may conflict with
  `gcp.resourceLocations`.
- Application state outside these services (queues, caches, object stores you
  did not tag, third-party SaaS data).
- SaaS products (Supabase, Vercel): rely on the vendor's recovery features and
  agreements. This repository does not back up their data.
- The cross-region copy region must differ from the home region and be in
  `aws.allowed_regions`. This is documented on the `dr_region` input. No plan
  check enforces it today (see [`known-gaps.md`](../known-gaps.md)).

## Restore procedures

These are the paths the landing zone supports. They have not been exercised
against a real apply. Write down the exact steps you use in your first drill.

1. **AWS resource from a member-account vault.**
   `aws backup list-recovery-points-by-backup-vault --backup-vault-name org-backup-vault`
   in the workload account, then `aws backup start-restore-job` with the
   recovery point ARN, the IAM role and the resource-type metadata
   (`aws backup get-recovery-point-restore-metadata` shows it). The vault
   uses a customer managed key when the CMK member vault is on, so the restore
   role needs that key.
2. **AWS resource from the central copy vault after loss of the workload
   account.** In the backup account, list recovery points in
   `org-backup-copy-vault`. Copy the recovery point into a vault in a new or
   recovered account with an AWS Backup copy job, then restore as in step 1. The
   vault access policy admits only the organization, so use a principal inside
   the organization. The lock stops deletion of copies, not reads.
3. **AWS resource in the DR region.** Restore from the DR-region vault in the
   workload account. The landing zone does not build a network in the DR region. Create
   the target network and subnets yourself, then restore into them.
4. **Aurora to a point in time.** `aws rds restore-db-cluster-to-point-in-time`
   into a new cluster, then repoint the application. Remove the old cluster
   through Terraform, not by hand.
5. **Cloud SQL to a point in time.** `gcloud sql instances clone <source> <new>
   --point-in-time=<UTC timestamp>`, then repoint the application and adopt the
   new instance into Terraform state.
6. **Cloud SQL from the Backup and DR vault.** List backups with
   `gcloud backup-dr backups list` in the host project and restore from the
   Backup and DR console or API into a new instance.
7. **Terraform state from the write-once bucket.** Follow
   [`state-backup.md`](state-backup.md#restore).
8. **Everything else.** Re-apply the roots in bootstrap order from Git. Do not
   run `terraform apply` locally against GCP roots: use HCP Terraform
   ([`apply-recovery.md`](apply-recovery.md)).

## Test schedule

- AWS Backup restore testing runs weekly once the central copy is on (BCK-02).
  Read its job results.
- Run a full exercise at least once a year, with an account-loss scenario and a
  project-loss scenario. Record the start time, the time each asset was usable,
  the data you lost, and the steps that failed.
- After the drill, replace the design targets in the table above with the
  measured RPO and RTO, and state the date of the drill.

## See also

- [`state-backup.md`](state-backup.md): off-platform copy and restore of state.
- [`teardown.md`](teardown.md) and [`aws-teardown.md`](aws-teardown.md): vault
  locks and immutability that limit deletion.
- [Control matrix](../compliance/control-matrix.md): BCK-01 to BCK-07.
- [Regulated environments](../architecture/regulated-environments.md): the
  class that turns the Backup and DR vault on.
