# Runbook: Move the Organization Trail to the CloudTrail Delegated Administrator

**When to use:** You are turning on `aws.enable_cloudtrail_delegated_admin` on an
estate whose organization trail (`org-trail`) is managed by the management
account's `aws-security` role. Afterwards the security-tooling account manages a
new organization trail, so the deny-tamper SCP applies to every change to it,
and the management role holds no trail write. The decision is
[ADR 0012](../adr/0012-cloudtrail-delegated-admin.md).

**The rule of this runbook:** there is never a moment without an organization
trail. The new trail is created next to the old one under a different name,
proven, and only then is the old one deleted, with break-glass.

**Time:** About two hours of applies and checks, plus a soak of at least one
hour (one digest cycle) before step 3.
**Risk:** Medium. Nothing stops logging if the steps run in order. During the
overlap both trails record management events, and the second copy is billed.
**Prerequisites:**

- The release with `enable_cloudtrail_delegated_admin` merged, and
  `aws-organization` and `aws-security` applied on it with the flag still off
  (they plan no change).
- Management-account break-glass ([`aws-break-glass.md`](aws-break-glass.md)).
- The AWS CLI, and the Terraform CLI logged in to HCP Terraform with write access
  to the `aws-security` workspace state (`terraform login`).
- The security-tooling account ID, the management account ID, the organization
  ID and `org.regions.aws` (the trail's home Region).

**Greenfield estates skip the migration.** Before the first `aws-organization`
apply, set `aws.enable_cloudtrail_delegated_admin: true` and
`aws.create_management_trail: false`, and leave `aws.adopt` without a
`cloudtrail_delegated_admin_account_id`. `aws-organization` registers security
tooling through CloudTrail, and `aws-security` creates only the delegated-admin
trail. The scaffolder leaves the flag off until this path is proven in the
sandbox.

---

## What changes

| Before | After |
|---|---|
| `aws-security` creates `org-trail` with the management provider (`module.cloudtrail[0]`). | It creates `org-trail-delegated` with the security-tooling provider (`module.cloudtrail_delegated_admin[0]`). The management account still owns the trail: its ARN is `arn:aws:cloudtrail:<home>:<management>:trail/org-trail-delegated`. |
| The trail's CloudWatch Logs group, delivery role, CMK, CIS alarms and alarm topic are in the management account. | They are in security tooling. CloudTrail requires the log group and role in the calling account. The delivery role carries the `tfc-apply` permissions boundary. |
| `aws-security` registers `cloudtrail.amazonaws.com` through the generic Organizations API (`security-delegated-admin`). | `aws-organization` registers it through CloudTrail (`aws_cloudtrail_organization_delegated_admin_account`), which also creates the CloudTrail service-linked roles. |
| The `tfc-mgmt-aws-security-apply` role holds `cloudtrail:*` on `org-trail` (`OrganizationTrailOnly`) and may pass the delivery role. | It holds no trail write, and may neither register nor deregister `cloudtrail.amazonaws.com`. Its trail and key denies stay. |
| SCPs never apply: the trail is managed from the management account. | `DenyDisableSecurityServices` (stop/delete: break-glass only), `DenyWeakenSecurityServices` (selectors/updates: pipeline roles and break-glass) and `DenyCentralDetectionOutsideSecurityAccounts` (only from the security accounts) apply. No new SCP statement. |

Facts the order depends on:

- CloudTrail rejects a second delegated-admin registration
  (`AccountRegisteredException`). An existing estate already has one, made by
  `aws-security`, so `aws-organization` imports it
  (`aws.adopt.cloudtrail_delegated_admin_account_id`).
- Terraform cannot drop one `for_each` key from state without destroying it, so
  `aws-security` forgets its copy of the registration with `terraform state rm`
  (step 1.3). If you skip it the plan shows a destroy, and the apply fails
  closed: the management role may not deregister `cloudtrail.amazonaws.com`.
- While the flag is on and `create_management_trail` is true (the default), the
  old trail stays in `aws-security`'s configuration, so Terraform plans no
  change to it. The management role cannot delete it either
  (`DenyTrailAndKeyDestruction`), and `destroy_guard` stops a CloudTrail delete.
  Only break-glass deletes it (step 3).
- Removing a delegated administrator never deletes the trails it created: the
  management account owns them.

---

## Steps

### 1. Create the new trail from the delegated admin

1. Record the current state, from the management account:

   ```bash
   aws organizations list-delegated-administrators --service-principal cloudtrail.amazonaws.com
   aws cloudtrail describe-trails --trail-name-list org-trail
   aws iam get-role --role-name AWSServiceRoleForCloudTrail --query Role.Arn
   ```

   The first must list the security-tooling account. If it lists nothing,
   leave `cloudtrail_delegated_admin_account_id` out in 1.2 (the registration is
   then created, not imported).

2. In `config/landing-zone.yaml`:

   ```yaml
   aws:
     enable_cloudtrail_delegated_admin: true
     adopt:
       cloudtrail_delegated_admin_account_id: "<security-tooling account ID>"
   ```

   Plan `aws-organization`. Expect exactly:
   - an **import** of `module.aws_organization.aws_cloudtrail_organization_delegated_admin_account.this[0]`;
   - an in-place update of the `tfc-apply-least-privilege` policy on
     `tfc-mgmt-aws-security-apply` (and of the teardown policy, if present).

   No destroy. Apply.

3. Before `aws-security` applies, remove its copy of the registration from its
   state. Lock the workspace in HCP Terraform, then:

   ```bash
   cd envs/aws/security
   TF_WORKSPACE=aws-security terraform init
   TF_WORKSPACE=aws-security terraform state rm \
     'module.aws_security.module.delegated_admin.aws_organizations_delegated_administrator.this["cloudtrail.amazonaws.com"]'
   ```

   Nothing changes in AWS. Unlock the workspace.

4. Plan `aws-security`. Expect only creates, all in security tooling, under
   `module.aws_security.module.cloudtrail_delegated_admin[0]`: the trail
   `org-trail-delegated`, its log group, delivery role and policy, CMK and
   alias, CIS alarm topic and subscriptions, and the CIS metric filters and
   alarms. If `break_glass_role_arn` is set, the security-notifications
   break-glass metric alarm on the new log group is also created.

   `module.aws_security.module.cloudtrail[0]` must show **no change**. Any
   destroy, of the old trail or of the registration, means a step was skipped:
   discard the run and go back. Apply.

### 2. Verify delivery

Wait for the first delivery (about 15 minutes), then from security tooling:

```bash
TRAIL=arn:aws:cloudtrail:<home>:<management>:trail/org-trail-delegated
aws cloudtrail get-trail-status --name "$TRAIL" --region <home>
```

- `IsLogging` is true, and `LatestDeliveryTime`,
  `LatestCloudWatchLogsDeliveryTime` and `LatestDigestDeliveryTime` are recent.
- `LatestDeliveryError`, `LatestCloudWatchLogsDeliveryError` and
  `LatestNotificationError` are absent. A KMS or S3 error here means the log CMK
  or bucket policy rejected the new trail: stop, the old trail still logs.
- The log group `/aws/cloudtrail/org-trail-delegated` in security tooling has
  streams named `<org-id>_<account>_CloudTrail_<region>` for several accounts.
- Digest files named `..._CloudTrail-Digest_<region>_org-trail-delegated_...`
  appear under `s3://<log-archive bucket>/AWSLogs/<org-id>/`. After an hour:
  `aws cloudtrail validate-logs --trail-arn "$TRAIL" --start-time <creation time>`.
- Confirm the email subscriptions to `org-trail-delegated-cis-alarms`, then
  test the path: `aws cloudwatch set-alarm-state --alarm-name
  org-trail-delegated-cloudtrail-config-changes --state-value ALARM
  --state-reason test`.
- Optional, while the old trail still logs: from a non-exempt admin role in
  security tooling, `aws cloudtrail stop-logging --name "$TRAIL"` must fail
  with an explicit SCP deny. If it succeeds, run `start-logging` at once and
  stop here: the deny-tamper SCP is not attached.

Let the two trails overlap for at least one hour (one digest cycle).

### 3. Delete the old trail with break-glass

1. Assume the management-account break-glass role
   ([`aws-break-glass.md`](aws-break-glass.md)) and, in the home Region:

   ```bash
   aws cloudtrail delete-trail --name arn:aws:cloudtrail:<home>:<management>:trail/org-trail
   ```

2. Lock the `aws-security` workspace, remove the old trail module from state,
   and turn it off in the same change:

   ```bash
   TF_WORKSPACE=aws-security terraform state rm 'module.aws_security.module.cloudtrail[0]'
   ```

   ```yaml
   aws:
     create_management_trail: false
   ```

   Unlock and plan `aws-security`: no change. A plan that creates `org-trail`
   means `create_management_trail` is not false yet (the apply would fail: the
   management role has no `CreateTrail`). A plan that destroys it means the
   state step was skipped.

3. The old trail's log group, CMK, topic, metric filters and alarms in the
   management account are now unmanaged. Keep them while the log group's
   retention matters; retire them in step 4.

### 4. Move the CIS alarms

The new trail already has the full CIS 4.1-4.15 set on its own log group and
topic (step 1.4), with the same `cloudtrail_cis_alarms_excluded` and
subscribers. What is left:

- Re-point anything that read the old log group or topic: dashboards, SIEM
  subscriptions, Logs Insights queries, and an external
  `cloudtrail_alarm_sns_topic_arn` (not carried over: the new alarms publish to
  their own topic in security tooling).
- With break-glass in the management account, delete the old alarms
  (`org-trail-*`), metric filters and topic. Delete the log group
  `/aws/cloudtrail/org-trail` when its retention no longer matters, and only
  then schedule deletion of the old CloudWatch CMK (`alias/org-trail-cloudwatch`).
- The trail delivery role `org-trail-cloudwatch-delivery` belongs to
  `aws-organization`. Set `create_org_trail_delivery_role = false` there to
  remove it.
- Remove `aws.adopt.cloudtrail_delegated_admin_account_id`: the registration is
  in state, so the import is a no-op either way.

---

## Rollback

Before step 3, the old trail still logs, so rolling back only removes the new
one. The SCP denies `DeleteTrail` to everyone but break-glass:

1. With the security-tooling break-glass role, delete `org-trail-delegated`.
2. In `aws-security`, `terraform state rm 'module.aws_security.module.cloudtrail_delegated_admin[0]'`,
   then delete its log group, alarms and topic with break-glass, and keep its CMK
   until the log group is gone.
3. In `aws-organization`, `terraform state rm 'module.aws_organization.aws_cloudtrail_organization_delegated_admin_account.this[0]'`
   (the registration stays), and set `aws.enable_cloudtrail_delegated_admin: false`.
4. In `aws-security`, `terraform import` the registration back:
   `'module.aws_security.module.delegated_admin.aws_organizations_delegated_administrator.this["cloudtrail.amazonaws.com"]'`
   with ID `<security-tooling account ID>/cloudtrail.amazonaws.com`. Then plan
   both roots: no change.

After step 3 there is no rollback to the management trail: create a new one
only by reversing the whole migration in the other direction, with the same
overlap.
