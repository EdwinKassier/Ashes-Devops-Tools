# Terraform State Backup and Restore

**When to use:** to set up the off-platform copy of Terraform state, or to
restore a workspace's state after HCP Terraform lost it (an organization or
workspace deleted, a compromised owner token, a bad state upload you can no
longer roll back in the UI).

HCP Terraform keeps every state version of a workspace, and
[apply-recovery](apply-recovery.md#3-rolling-back-to-a-previous-state-version)
covers rolling back within it. That history lives in one place, though. The
scheduled workflow
[`.github/workflows/state-backup.yml`](../../.github/workflows/state-backup.yml)
copies each workspace's current state version to a versioned, write-once bucket
in AWS, GCP or both.

## How it works

- Runs daily at 05:30 UTC and on manual dispatch.
- Lists every workspace the backup token can see. For each one it downloads the
  current state version, checks that the file is state JSON whose `serial`
  matches HCP Terraform, and uploads it as
  `<prefix><org>/<workspace>/<created-at>_serial-<n>_<state-version-id>.tfstate`.
  An object that already exists is never overwritten, so the bucket keeps every
  version the workflow has seen.
- Authenticates to the clouds with GitHub OIDC only. No static keys exist.
- Fails closed. With no token or no complete target, the run fails. Any
  workspace that cannot be exported fails the run. A workspace with no state
  yet is reported, not failed. The repository variable
  `STATE_BACKUP_OPT_OUT=true` turns an unconfigured scheduled run into a
  warning, never into a silent pass.

State files hold sensitive values (generated passwords, private keys, tokens).
Treat the bucket, the token and the cloud roles as you treat HCP Terraform
itself.

## Setup

### 1. HCP Terraform team and token

1. An organization owner creates a dedicated team, for example `state-backup`,
   with no organization permissions.
2. Set its ID as `state_backup_team_id` on `envs/tfc-admin` and apply. tfc-admin
   grants it custom access on every project except the security-only guardrails
   project: `state_versions = read`, `runs = read`, `variables = none`. A
   precondition rejects a team that already holds another grant.
3. `gcp-guardrails` lives in the guardrails project, where only the security
   team has access. To back it up as well, the security team grants the backup
   team the same custom permissions on that project by hand. Otherwise it is
   not exported, and `STATE_BACKUP_WORKSPACES` must not list it.
4. A self-managed `tfc-admin` workspace sits in the platform project, which is
   included. A hand-created one outside any managed project needs the same
   grant by hand.
5. Create a team token with an expiry (at most 90 days) and store it as the
   secret `TFC_TOKEN_STATE_BACKUP` in a GitHub environment named
   `tfc-state-backup`, with deployment branches limited to `main`
   ([CI secrets](../guides/CI_SECRETS.md#environment-scoped-secrets)).

### 2. AWS target (optional)

In an account outside the workload accounts (the log-archive or backup account):

1. Create an S3 bucket with **versioning** and **Object Lock** enabled, a
   default retention (compliance mode, for example 90 days), SSE-KMS with a
   customer-managed key, Block Public Access on, and a bucket policy that
   denies non-TLS requests.
2. Create an IAM role trusted by the GitHub OIDC provider
   (`token.actions.githubusercontent.com`) with `aud = sts.amazonaws.com` and
   `sub = repo:<owner>/<repo>:environment:tfc-state-backup`. Allow only
   `s3:PutObject`, `s3:GetObject` and `s3:ListBucket` on the bucket and prefix,
   and `kms:GenerateDataKey` / `kms:Encrypt` on the key. Do not allow delete,
   `PutObjectRetention`, `PutBucketObjectLockConfiguration` or bypass of
   governance retention.
3. Set the repository variables `STATE_BACKUP_S3_BUCKET`,
   `STATE_BACKUP_AWS_ROLE_ARN` and `STATE_BACKUP_AWS_REGION`.

### 3. GCP target (optional)

In a project outside the workload folders (the admin or logging project):

1. Create a bucket with uniform bucket-level access, public access prevention
   enforced, a CMEK key and a **retention policy**, then **lock** the policy
   (Bucket Lock). GCS does not allow Object Versioning together with a
   retention policy. Unique object names and the locked retention give the
   same guarantee: no object is overwritten or deleted before it expires.
2. Create a Workload Identity pool provider for GitHub with an attribute
   condition that pins the repository owner ID and the `tfc-state-backup`
   environment, and a service account with `roles/storage.objectCreator` and
   `roles/storage.objectViewer` on the bucket only (no admin, no delete).
   Grant the provider's principal `roles/iam.workloadIdentityUser` on the
   service account.
3. Set the repository variables `STATE_BACKUP_GCS_BUCKET`,
   `STATE_BACKUP_GCP_WIF_PROVIDER` and `STATE_BACKUP_GCP_SA`.

### 4. Optional variables

- `STATE_BACKUP_WORKSPACES`: a JSON array of workspace names that must be
  exported, for example `["tfc-admin","gcp-bootstrap","gcp-organization"]`. A
  listed workspace the token cannot see fails the run, so a lost grant shows
  up.
- `STATE_BACKUP_PREFIX`: object-name prefix, default `tfstate/`.

Run the workflow once by hand (Actions, Terraform State Backup, Run workflow)
and check the summary table: every workspace should be newly exported or
already in the bucket.

## Restore

Restore the latest good object for each workspace you lost. Work from a
trusted machine; the files contain secrets. Delete local copies afterwards.

### 1. Pick the object

```bash
# AWS
aws s3 ls "s3://<bucket>/tfstate/<org>/<workspace>/"
aws s3 cp "s3://<bucket>/tfstate/<org>/<workspace>/<object>.tfstate" ./restore.tfstate
# GCP
gcloud storage ls "gs://<bucket>/tfstate/<org>/<workspace>/"
gcloud storage cp "gs://<bucket>/tfstate/<org>/<workspace>/<object>.tfstate" ./restore.tfstate

jq '{serial, lineage, terraform_version}' restore.tfstate
```

The newest object (highest `serial`) is the last state the workflow saw. Up to
one day of applies can be newer than the backup: read those runs' logs and
expect the next plan to show their resources as changes to import or to
re-create.

### 2. Recreate the workspaces if they are gone

If only some workspaces are lost, re-apply `tfc-admin`: it recreates the
missing workspaces with their settings, variables, team access and policy sets.

If the whole organization is lost:

1. Recreate the organization, the hand-created teams (`platform`, `approvers`,
   `security`, `tfc-admin`, `state-backup`, the saas readers) and the
   hand-created `tfc-admin` workspace
   ([bootstrap](bootstrap.md)).
2. Restore `tfc-admin`'s state first (steps 3 and 4 below), then plan and
   apply it. Team IDs change when teams are recreated: update
   `platform_team_id` and the other team inputs before the apply. tfc-admin
   recreates the other workspaces. Their IDs change, so `gcp-bootstrap`'s
   `tfc_workspace_ids` changes too, and the WIF bindings follow on its next
   apply.
3. Restore the other workspaces in the run-trigger order: `gcp-bootstrap` and
   `aws-organization`, then the control plane, then the hubs, then the
   workloads and `saas-*`.

### 3. Push the state

Lock the workspace (Settings, Locking) so no run starts during the restore. A
state push into a new, empty workspace needs no `-force`. Into a workspace that
already has newer, wrong state, `-force` replaces it; read the serials first.

```bash
cd envs/<cloud>/<root>             # the workspace's working directory
export TF_CLOUD_ORGANIZATION=<org>
export TF_WORKSPACE=<workspace>    # e.g. gcp-workload-prod
terraform init -input=false
terraform state push ./restore.tfstate          # or: -force, see above
rm -f ./restore.tfstate
```

`state push` refuses a file whose lineage differs from the workspace's
existing state unless you pass `-force`. A brand-new workspace has no lineage,
so the push takes the backup's.

### 4. Verify

1. Unlock the workspace and queue a plan (not an apply) from HCP Terraform.
2. A plan with no changes, or only the changes made after the backup, confirms
   the restore. A plan that wants to create resources that exist means the
   state is older than the infrastructure: import them, or restore a newer
   object if there is one.
3. Run the drift check for the workspace (Actions, Drift Detection, Run
   workflow) once it has applied again.

## Related

- [Recovering a failed or partial apply](apply-recovery.md)
- [CI secrets and variables](../guides/CI_SECRETS.md)
- [`envs/tfc-admin`](../../envs/tfc-admin/README.md) (`state_backup_team_id`)
