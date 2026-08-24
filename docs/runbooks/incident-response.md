# Runbook: GCP Incident Response — Quarantine & Forensics

**When to use:** Security Command Center (or an operator) has flagged a compromised or suspect GCP project, VM, or identity and you need to isolate it, preserve evidence, and analyze it without contaminating the source environment. This is the GCP counterpart to [`aws-incident-response.md`](aws-incident-response.md).

**Time:** Containment is a manual/scriptable procedure (minutes, once you act); forensic analysis is open-ended.
**Risk:** High. You are operating on a live, possibly-compromised project and moving evidence between projects. Preserve first, remediate second; do not delete disks, keys, or the offending project before snapshots and audit copies exist.
**Prerequisites:** The GCP organization layer is applied (`envs/gcp/organization`), you know the org ID and the admin project that hosts the `scc-findings` topic and the audit-logs sink, and you hold — or have an approver who holds — `roles/resourcemanager.organizationAdmin` for org-scoped containment actions.

---

> **GCP ships no automated isolation function.** Unlike the AWS side (which wires a GuardDuty finding through EventBridge to an `ir-isolate` Lambda in `modules/aws/security/incident-response`), there is **no packaged auto-isolation module on GCP**. Everything below Step 1 is a **manual, operator-driven procedure** you run with `gcloud`/Terraform. Detection is automated (SCC → Pub/Sub, org audit sink); containment and forensics are not. See [Honest gaps](#honest-gaps).

> Evidence handling: snapshot **before** you change anything you can avoid changing. Isolation (cutting networking, disabling identities) is acceptable and expected; deleting disks, key versions, or the project destroys volatile state and must wait until forensic copies are confirmed.

---

## Detection — where the signal comes from

Two independent, CMEK-protected sources feed an investigation. Both are stood up by the organization layer (`modules/gcp/stages/organization`):

| Source | What it is | Where |
|---|---|---|
| **SCC findings** | `modules/gcp/governance/scc` creates the **`scc-findings`** Pub/Sub topic (CMEK-encrypted via the `scc-notifications` key) and a notification config (`scc-notify-all-active`) that streams every finding matching **`state="ACTIVE"`** to it. The SCC service account holds `roles/pubsub.publisher` on the topic. | Admin project, topic `scc-findings` |
| **Org audit logs** | `modules/gcp/governance/cloud-audit-logs` runs an **organization sink** (`org-audit-sink`, `include_children = true`) exporting `logName:cloudaudit.googleapis.com` into the CMEK GCS bucket **`<admin-project>-audit-logs`** (versioning on, retention via lifecycle), plus a BigQuery analytics sink (`org-audit-logs-bq-analytics` → dataset `org_audit_logs_analytics`) for Admin Activity + Policy logs. | Admin project bucket + BigQuery |

The SCC stream tells you **something is wrong**; the audit logs are the **forensic record** of what happened.

> The severity-routing variant (`notification_configs` in `modules/gcp/governance/scc`) can split `CRITICAL`/`HIGH` from `MEDIUM`/`LOW` into separate topics. The organization layer ships the single all-active config by default — triage severity from the finding payload.

### Subscribe & triage

Pull recent findings off the topic (create an ephemeral subscription if one is not already attached):

```bash
gcloud pubsub subscriptions create ir-triage \
  --topic=scc-findings --project=ADMIN_PROJECT_ID

gcloud pubsub subscriptions pull ir-triage \
  --project=ADMIN_PROJECT_ID --auto-ack --limit=20 \
  --format="table(message.data.decode('base64'))"
```

Cross-reference the finding's `resourceName` against the audit trail in BigQuery to establish a timeline:

```bash
bq query --use_legacy_sql=false \
'SELECT timestamp, protopayload_auditlog.methodName,
        protopayload_auditlog.authenticationInfo.principalEmail,
        resource.labels.project_id
 FROM `ADMIN_PROJECT_ID.org_audit_logs_analytics.cloudaudit_googleapis_com_activity_*`
 WHERE resource.labels.project_id = "COMPROMISED_PROJECT_ID"
 ORDER BY timestamp DESC LIMIT 100'
```

---

## Step 1 — Contain the network (deny-all)

External IPs are **already denied org-wide** — `compute.vmExternalIpAccess` is set with `deny_all = true` in `modules/gcp/stages/organization` (CIS 4.9), so a compromised VM cannot reach the internet directly through a public IP. Containment therefore targets **internal reachability and egress**.

The host stack (`modules/gcp/stages/host`) already lays down a tiered firewall with a **deny-all ingress rule at priority 65535** and a **deny-egress rule on the database tier at 65534** (both via `modules/gcp/network/network-firewall`). To quarantine a specific instance, add a higher-priority (lower number) deny rule scoped to its network tag, so it overrides the tier allow-rules:

```bash
# Deny ALL egress from the compromised instance's tag (priority beats the tier allows)
gcloud compute firewall-rules create ir-quarantine-egress \
  --project=COMPROMISED_PROJECT_ID --network=VPC_NAME \
  --direction=EGRESS --action=DENY --rules=all \
  --priority=100 --target-tags=QUARANTINE_TAG --enable-logging

# Deny ALL ingress to it as well
gcloud compute firewall-rules create ir-quarantine-ingress \
  --project=COMPROMISED_PROJECT_ID --network=VPC_NAME \
  --direction=INGRESS --action=DENY --rules=all \
  --priority=100 --target-tags=QUARANTINE_TAG --enable-logging

# Apply the quarantine tag to the instance (this is what severs it)
gcloud compute instances add-tags INSTANCE_NAME \
  --project=COMPROMISED_PROJECT_ID --zone=ZONE --tags=QUARANTINE_TAG
```

Leaving the instance **running** preserves volatile state for imaging — do not stop or delete it yet.

To cut inbound to an **entire folder or the org** (broader blast radius), add a deny rule to a **hierarchical firewall policy** (`modules/gcp/network/hierarchical-firewall`) associated at that level — it evaluates before per-VPC rules across every project underneath.

---

## Step 2 — Tighten the perimeter (VPC Service Controls)

If exfiltration is suspected, put a VPC-SC perimeter around the affected project — or flip an existing dry-run perimeter to enforcing — to stop data leaving via Google APIs (Storage, BigQuery, etc.). The `modules/gcp/network/vpc-sc` module controls this with **`enable_dry_run`**:

- `enable_dry_run = true` renders a **`spec` block only** — violations are logged, not blocked (safe to observe first).
- `enable_dry_run = false` renders the **`status` block** — the perimeter is **enforced** and denies access to `restricted_services` from outside the perimeter.

During an incident, add the compromised project to `protected_projects` and set `enable_dry_run = false` (via `var.vpc_service_controls` in the host stack, or a dedicated perimeter in the org layer), then apply. Because the perimeter carries deletion protection (`enable_deletion_protection`, default `true`), it cannot be torn down by an attacker in the same breath.

> Bridge perimeters (`PERIMETER_TYPE_BRIDGE`) do **not** support dry-run — the module guards against that combination. Use a regular perimeter for enforcement.

---

## Step 3 — Revoke identity & credentials

GCP org policy has **already removed the worst credential vector**: `iam.disableServiceAccountKeyCreation` **and** `iam.disableServiceAccountKeyUpload` are both enforced in `modules/gcp/stages/organization`, so long-lived SA JSON keys cannot exist to be stolen. Credential response therefore focuses on **federated access and live bindings**, not key files.

1. **Disable the offending service account** (`modules/gcp/iam/service-account`) — this halts everything acting as it:

   ```bash
   gcloud iam service-accounts disable \
     SA_EMAIL --project=COMPROMISED_PROJECT_ID
   ```

2. **Revoke IAM bindings** the attacker gained or the SA no longer needs. Capture the current policy first (evidence), then remove the binding:

   ```bash
   gcloud projects get-iam-policy COMPROMISED_PROJECT_ID --format=json \
     > /tmp/iam-policy-before-$(date +%s).json
   gcloud projects remove-iam-policy-binding COMPROMISED_PROJECT_ID \
     --member="MEMBER" --role="ROLE"
   ```

3. **Cut Workload Identity Federation access** (`modules/gcp/iam/workload-identity`) — since federation, not keys, is how CI authenticates. Disable the pool or provider so no external token can mint GCP credentials:

   ```bash
   gcloud iam workload-identity-pools update POOL_ID \
     --location=global --project=ADMIN_PROJECT_ID --disabled
   ```

   Or tighten the provider's attribute condition (repo/ref scoping) if only one repository is implicated. If the WIF pipeline itself is the compromised path — and you need emergency access to remediate — follow [`break-glass.md`](break-glass.md).

4. **Rotate secrets** the workload could read (Secret Manager entries, DB passwords, third-party tokens) and **disable the relevant CMEK key version** so anything the attacker encrypted or could decrypt is cut off:

   ```bash
   gcloud kms keys versions disable VERSION \
     --key=KEY --keyring=KEYRING --location=LOCATION --project=ADMIN_PROJECT_ID
   ```

   Rotate the key to a new primary version for legitimate workloads once scope is understood.

---

## Step 4 — Preserve forensic evidence

1. **Snapshot every attached disk** on the affected VM, tagged for chain of custody, **before** any teardown:

   ```bash
   gcloud compute disks snapshot DISK_NAME \
     --project=COMPROMISED_PROJECT_ID --zone=ZONE \
     --snapshot-names="ir-TICKET-$(date -u +%Y%m%dT%H%M%SZ)" \
     --labels=incident=TICKET,source-project=COMPROMISED_PROJECT_ID
   ```

2. **Copy the snapshot into an isolated analysis project/folder** (a clean-room with no production connectivity), and mount a volume from it **there** — never back in the source project, so tooling never touches the compromised environment:

   ```bash
   gcloud compute snapshots create ir-TICKET-copy \
     --project=FORENSICS_PROJECT_ID \
     --source-snapshot=projects/COMPROMISED_PROJECT_ID/global/snapshots/ir-TICKET-...
   ```

3. **Preserve the audit logs.** The `<admin-project>-audit-logs` bucket already has **versioning enabled** and a **retention lifecycle** (`modules/gcp/governance/cloud-audit-logs`), so the record is tamper-evident, but export the incident window to an immutable, incident-scoped location so retention cleanup can never age it out mid-investigation:

   ```bash
   gcloud logging read \
     'logName:cloudaudit.googleapis.com AND resource.labels.project_id="COMPROMISED_PROJECT_ID"' \
     --project=ADMIN_PROJECT_ID --freshness=7d --format=json \
     > /tmp/incident-audit-TICKET-$(date +%Y%m%d).json
   ```

   Keep source snapshots and log exports **immutable**; analyze copies only.

---

## Step 5 — Eradicate & recover

Only after forensic copies are confirmed:

1. Delete or rebuild the compromised VM (or quarantine the whole project via the org hierarchy).
2. Confirm every credential the workload could reach is rotated/revoked (Step 3) and the disabled CMEK version is accounted for.
3. Review the org audit sink (GCS bucket + BigQuery) for **lateral movement** into other projects — `SetIamPolicy`, cross-project data reads, new SA impersonation grants.
4. Restore clean workloads from backup and re-apply the affected environment through Terraform Cloud (never a local `apply` against the org/workload roots).
5. Once the perimeter change and quarantine firewall rules are no longer needed, revert them through Terraform so the baseline is restored — do not leave ad-hoc `gcloud`-created rules in place.

---

## Step 6 — Post-incident review

Within 24 hours, document the timeline, root cause, blast radius, and remediation. Confirm the quarantine firewall rules, VPC-SC change, snapshots, and log exports are all accounted for and that no evidence was destroyed. If break-glass access was used during the response, cross-check every action taken with it per [`break-glass.md`](break-glass.md).

---

## Honest gaps

- **No packaged auto-isolation.** There is no GCP equivalent of the AWS `ir-isolate` Lambda — containment here is the manual/scriptable procedure above, not a module you can rely on to fire on a finding. If you need automation, wire an SCC → Pub/Sub → Cloud Functions/Cloud Run subscriber yourself; it is not part of this landing zone today.
- **Detection is automated; response is not.** SCC notifications and the org audit sink are Terraform-managed; the quarantine, perimeter flip, and credential revocation are operator actions.
- Any incident-response items still open or unvalidated are tracked in [`docs/known-gaps.md`](../known-gaps.md), not inline here.

---

## See also

- [AWS Incident Response](aws-incident-response.md) — the automated (Lambda-based) counterpart this mirrors.
- [Break-Glass Emergency Access](break-glass.md) — emergency GCP access when WIF/CI is the compromised path.
- [GCP Landing Zone](../architecture/gcp-landing-zone.md#security-services) — where SCC, audit logging, org policy, and VPC-SC sit in the design.
