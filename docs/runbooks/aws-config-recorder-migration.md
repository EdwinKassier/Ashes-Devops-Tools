# Runbook: AWS Config Recorder Migration (workload roots to the org StackSet)

**When to use:** You are upgrading an estate whose workload accounts have Config
recorders managed by the `aws-workload-<env>` roots (`module.config_recorder`).
The recorders move to an org-wide service-managed StackSet owned by
`aws-organization`, and then the recorder SCP locks them down.

**Greenfield estates skip the migration.** On a new estate no workload root
creates a recorder. Leave both flags `false` for the first `aws-organization`
apply. Once `aws-security` has applied, set both to `true`
(`scripts/init-landing-zone.sh --aws-config-recorders true`, or edit
`aws.enable_org_config_recorders` and `aws.enable_config_recorder_scp`), then
re-apply `aws-organization`.

**Time:** About an hour of applies. Each account has a recording gap of a few
minutes, from step 4 to step 5.
**Risk:** Medium. Step 4 deletes live recorders. Until step 5 completes, nothing
records configuration changes in that account.
**Prerequisites:**

- Break-glass access to the management account. The member-account break-glass
  role must exist in every workload account (`enable_member_break_glass_role`).
- The AWS CLI.
- The list of workload account IDs and their enabled Regions, and the
  security-tooling account ID (the script refuses to touch it).
- `org.regions.aws` (the aws-security home Region, `org_trail_home_region`)
  must be one of `aws.enabled_regions`. Only the home-Region recorder records
  global resource types, and the plan fails with the flag on otherwise.

---

## What changes

| Before | After |
|---|---|
| Each `aws-workload-<env>` root manages its account's recorder, delivery channel and recorder status. | The `org-config-recorders` StackSet (`modules/aws/security/config-recorder-stackset`) deploys them to every member account except security tooling. Accounts that join later are auto-deployed. |
| The management account has no recorder. | `aws-organization` gives it a direct recorder (StackSets never deploy to the management account). |
| Security tooling's recorder feeds the aggregator (`aws-security`). | Unchanged. |
| `DenyWeakenSecurityServices` exempts every pipeline role from the recorder actions. | `DenyConfigRecorderChanges` exempts only `stacksets-exec-*`, break-glass and `arn:aws:iam::<security_tooling>:role/tfc-apply`. |

Facts the order depends on:

- CloudFormation cannot adopt an existing recorder, and an account holds one
  customer recorder and one delivery channel per Region. A stack instance
  fails in any account that still has its legacy recorder.
- The StackSet uses its own names, `org-stackset-recorder` and
  `org-stackset-delivery`. The legacy names are `org-recorder` and
  `org-delivery`. `PutConfigurationRecorder` and `PutDeliveryChannel` are
  upserts by name, so a shared name would let CloudFormation silently take
  over a live legacy recorder. With distinct names the outcome of step 3 is
  deterministic: the instance fails in every account that still has a legacy
  recorder.
- Global resource types are gated inside the template on `AWS::Region` equal
  to the home Region, not by per-instance parameters. Auto-deployed accounts
  therefore get the same recording group.
- The template creates no IAM resources. The recorder uses the account's
  `AWSServiceRoleForConfig` service-linked role, the same role the workload
  recorder used by default. The SLR stays in the account when the workload
  root drops the recorder from state.
- The tfc-apply boundary already denies `tfc-apply` from stopping or deleting
  recorders, so the workload roots cannot delete them during the upgrade.

---

## Steps

### 1. Upgrade the workload roots

Merge the release and let each `aws-workload-<env>` workspace plan and apply.
The `removed { from = module.config_recorder  lifecycle { destroy = false } }`
block drops the recorder, delivery channel, recorder status and (if this root
created it) the Config SLR from state. **Nothing is deleted in AWS.**

Check the plan of each workspace: it must show the recorder resources as
"will no longer be managed by Terraform" and **no destroy**. A destroy means the
workspace is not on this release yet. Stop.

If you set `config_role_arn` or `create_config_service_linked_role`, remove
them. A check now warns about both.

### 2. Apply aws-security

Apply `aws-security` so that the log-archive bucket and its `AWSConfigWrite`
bucket-policy statement (scoped to `aws:SourceOrgID`) exist. The StackSet and
the management recorder deliver there.

### 3. Apply aws-organization with the recorders on, tolerating failures

Set these, then apply `aws-organization`:

```hcl
enable_org_config_recorders                       = true  # or aws.enable_org_config_recorders: true
org_config_recorders_failure_tolerance_percentage = 100   # TFC variable, this pass only
```

If Config was enabled in the management account before, also set
`create_management_config_service_linked_role = false`.

What to expect:

- The management account gets its direct recorder.
- Stack instances **succeed** in accounts that never had a recorder: the
  Infrastructure accounts, log archive, forensics, and any account vended later.
- They **fail** in accounts that still hold a legacy recorder. The error is
  `MaxNumberOfConfigurationRecordersExceededException` (the second customer
  recorder, `org-stackset-recorder`, beside `org-recorder`). If the recorder
  got through, it is `MaxNumberOfDeliveryChannelsExceededException` (a second
  channel). The legacy recorder is untouched either way.
- With tolerance 100 the apply still succeeds.

List the failed instances. These are the accounts for step 4:

```bash
aws cloudformation list-stack-instances --stack-set-name org-config-recorders \
  --query "Summaries[?StackInstanceStatus.DetailedStatus=='FAILED'].[Account,Region]" --output text
```

### 4. Delete the legacy recorders (break-glass)

From a management-account **break-glass** session, dry-run first:

```bash
scripts/aws-delete-legacy-recorders.sh \
  --accounts 333333333333,444444444444 --regions eu-west-2,eu-west-1 \
  --role-name break-glass --exclude-account <security_tooling_id>
```

Check the output. It must list only workload accounts and only the legacy
`org-recorder` / `org-delivery`.

The script refuses three things:

- **Security tooling.** An account passed in `--exclude-account` is refused
  before any AWS call.
- **Other names.** Recorders and channels without the legacy names are left
  alone and shown as `KEEP`. Override the names with `--legacy-recorder-name`
  / `--legacy-channel-name` if yours differ.
- **StackSet Regions.** A Region with a live `StackSet-org-config-recorders-*`
  stack is refused (`REFUSED`, non-zero exit), because the StackSet already
  records there.

Then delete:

```bash
scripts/aws-delete-legacy-recorders.sh \
  --accounts 333333333333,444444444444 --regions eu-west-2,eu-west-1 \
  --role-name break-glass --exclude-account <security_tooling_id> --execute
```

For each Region, the script stops the recorder, deletes the delivery channel,
then deletes the recorder. **Recording stops here.** Go straight to step 5.
Record the time of the first deletion.

### 5. Re-run the StackSet instances

Set `org_config_recorders_failure_tolerance_percentage = 0` (remove the TFC
variable) and re-apply `aws-organization`. If Terraform shows no change for the
failed instances, retry them directly:

```bash
aws cloudformation update-stack-instances --stack-set-name org-config-recorders \
  --deployment-targets OrganizationalUnitIds=<root-id>,Accounts=<security_tooling_id>,AccountFilterType=DIFFERENCE \
  --regions eu-west-2 eu-west-1
```

Every instance must reach `CURRENT`. Check that recording runs in each
migrated account and Region:

```bash
aws configservice describe-configuration-recorder-status --region eu-west-2
```

Record the time recording resumed. The gap is from step 4 to now.

### 6. Turn on the recorder SCP

Set `enable_config_recorder_scp = true` (or `aws.enable_config_recorder_scp:
true`) and apply `aws-organization`. Only the StackSet execution role,
break-glass and security tooling's `tfc-apply` (`security_tooling_apply_role_name`)
may then put, stop or delete a recorder, or put or delete a delivery channel.

Routine applies are unaffected:

- the security-tooling `tfc-apply` still manages the aggregator recorder;
- workload `tfc-apply` roles still create and replace flow logs.

---

## Rollback

- **Before step 4:** set `enable_org_config_recorders = false` and apply
  `aws-organization`. The StackSet instances and the management recorder are
  deleted, and the legacy recorders are untouched.
- **After step 4:** do not roll back. Finish step 5. The legacy recorders are
  gone, and the StackSet is now the only thing that records.
- **After step 6:** set `enable_config_recorder_scp = false` and apply. The
  recorder actions return to `DenyWeakenSecurityServices`.

## Notes

- **Changing the StackSet's deployment targets forces replacement.** This
  covers the org root and the excluded security-tooling account. Every
  instance is deleted and recreated, which means another short recording gap
  everywhere.
- The StackSet administrator (`aws-organization`) can deploy to every account.
  This is inherent to StackSets ([known gaps](../known-gaps.md)).
- Sandbox run: not yet performed. Record the measured gap here when it is.
