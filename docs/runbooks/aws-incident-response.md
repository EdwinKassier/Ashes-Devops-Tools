# Runbook: AWS Incident Response — Quarantine & Forensics

**When to use:** GuardDuty (or an operator) has flagged a compromised or suspect EC2 instance and you need to isolate it, preserve evidence, and analyze it in the Forensics account without contaminating the source environment. This is the operational counterpart to the auto-isolation wiring in `modules/aws/incident-response`.

**Time:** Isolation is near-immediate (automated); forensic analysis is open-ended.
**Risk:** High. You are operating on a live, possibly-compromised host and moving evidence between accounts. Preserve first, remediate second; do not terminate the instance before snapshots exist.
**Prerequisites:** The security layer is applied with `enable_incident_response = true`, the **Forensics** account exists, and you know the org ID (`aws:PrincipalOrgID` scope) and `forensics_account_id`.

---

> Evidence handling: snapshot **before** you change anything you can avoid changing. Isolation (detaching networking) is acceptable and expected; termination destroys volatile state and must wait until forensic copies are confirmed.

---

## Automated quarantine flow

`modules/aws/incident-response` wires this automatically in the security stage:

```text
GuardDuty finding (severity >= 7)
  -> EventBridge rule (ir-guardduty-high-severity)
    -> EventBridge target
      -> isolation Lambda (ir-isolate)
        -> attach quarantine security group to the flagged instance
```

The quarantine security group is a **deny-all** SG (no ingress, no egress) — attaching it severs the instance's network reachability while leaving it running and its EBS volumes intact for imaging.

> **The shipped Lambda (`files/isolate.py`) is an isolation scaffold** — it logs the finding and returns success. Extend it to actually attach the quarantine SG and, for forensics, to share an EBS snapshot with the Forensics account. Verify what your deployed version does before relying on it during an incident.

---

## Step 1 — Confirm isolation

Check that the instance received the quarantine SG (either by the Lambda or manually):

```bash
aws ec2 describe-instances --instance-ids <id> \
  --query 'Reservations[].Instances[].SecurityGroups'
```

If auto-isolation did not fire (or the Lambda is still the scaffold), attach the quarantine SG manually:

```bash
aws ec2 modify-instance-attribute --instance-id <id> --groups <quarantine-sg-id>
```

Do **not** stop or terminate the instance yet.

---

## Step 2 — Snapshot the evidence

Create EBS snapshots of every attached volume. Tag them so the chain of custody is auditable:

```bash
aws ec2 create-snapshot --volume-id <vol-id> \
  --description "IR <ticket> <instance-id> $(date -u +%FT%TZ)" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=incident,Value=<ticket>}]'
```

Capture instance metadata (AMI, tags, IAM role, network interfaces) to the ticket now — it may change or be lost later.

---

## Step 3 — Share snapshots into the Forensics account

Copy/share the snapshots into the **Forensics account clean-room** using the intra-org forensics role. The `ir-forensics-snapshot-share` role is trusted **only** by the Forensics account principal **and** further scoped by `aws:PrincipalOrgID` — so even if the account ID leaks, no principal outside the organization can assume it.

1. Share the snapshot with the Forensics account (or let the role perform the cross-account copy):

   ```bash
   aws ec2 modify-snapshot-attribute --snapshot-id <snap-id> \
     --attribute createVolumePermission --operation-type add \
     --user-ids <forensics-account-id>
   ```

2. From the **Forensics account**, assume `ir-forensics-snapshot-share` and copy the snapshot into a forensics-owned, KMS-encrypted volume. Because the sharing is scoped by `aws:PrincipalOrgID`, the copy stays inside the org trust boundary.

---

## Step 4 — Analyze in the clean-room

The **Forensics account** is an isolated SRA account (Security OU) with no production connectivity — a clean-room. Mount the copied volume on a forensic analysis instance **there**, never in the source account, so analysis tooling never touches the compromised environment. Keep the source snapshots immutable; analyze copies.

---

## Step 5 — Contain, eradicate, recover

Only after forensic copies are confirmed:

1. Terminate or rebuild the compromised instance.
2. Rotate any credentials/keys the instance's IAM role could reach.
3. Review the org CloudTrail (Log Archive account) for lateral movement.
4. Restore clean workloads from backup (the Backup account vaults — see [`aws-teardown.md`](aws-teardown.md) for the Vault Lock immutability note).

---

## Step 6 — Post-incident review

Within 24 hours, document timeline, root cause, blast radius, and remediation. Confirm the quarantine SG, snapshots, and forensic copies are all accounted for and that no evidence was destroyed. If break-glass access was used, cross-check it per [`aws-break-glass.md`](aws-break-glass.md).

---

## See also

- [AWS Landing Zone](../architecture/aws-landing-zone.md#incident-response--forensics) — where incident-response sits in the SRA.
- [AWS Break-Glass](aws-break-glass.md) — emergency access if normal paths are down.
- [AWS Teardown](aws-teardown.md) — backup/log immutability that affects recovery.
