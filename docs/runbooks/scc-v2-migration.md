# Runbook: Security Command Center v1 to v2 migration

**When to use:** moving the organization's SCC notification stream (and optional mute configs) from the v1 API to the v2 API (`google_scc_v2_organization_*`). SCC v1 is on a deprecation path; v2 is where new features land.

**Key fact:** v1 and v2 cannot see each other's configs. A v1 notification config does not stream v2 findings and a v2 config does not stream v1 findings, and mute configs are likewise per API generation. Flipping blind can therefore leave a gap in detection. This is why the module has three modes.

Input: `scc_api_version` on `modules/gcp/governance/scc`, set in the organization root through `gcp_overrides = { scc_api_version = "..." }` (it maps to `gcp.scc_api_version` in the stage object).

| Value | Creates | Notes |
|---|---|---|
| `v1` (default) | v1 notification config and publisher binding (and v1 mute configs) | Unchanged behaviour; nothing is planned for existing estates. |
| `both` | v1 resources plus the v2 twins | Verification window. Both write to the same Pub/Sub topic. |
| `v2` | v2 resources only | The v1 configs are destroyed. |

The Pub/Sub topics are shared by every mode, so they keep their addresses and are never replaced by a flip.

## 1. Create v2

1. Set `scc_api_version = "both"` and let the `gcp-organization` workspace plan and apply through Terraform Cloud. Never apply locally.
2. **Subscribers receive every finding twice, in two formats** (once from the v1 config, once from the v2 config) on the same topic. Before applying: make the subscriber idempotent or dedupe on the finding's resource name plus category and event time, tell on-call that duplicate alerts are expected during the window, and keep the window short (hours to a few days, not weeks). If alert noise is unacceptable, mute duplicates at the subscriber (drop v2-shaped messages until step 3 of Verify passes) rather than disabling v1.
3. The plan must show only additions: `google_scc_v2_organization_notification_config`, `google_pubsub_topic_iam_member.scc_publisher_v2` and, when `mute_configs` is set, the v2 mute configs.

## 2. Verify

1. List the v2 configs: `gcloud scc notifications list --organization=ORG_ID --location=global` (use the v2 location you configured in `scc_location`).
2. Confirm the v2 service account (output `scc_v2_notification_configs` on the `gcp-organization` workspace) holds `roles/pubsub.publisher` on the topic.
3. Wait for a real or test finding and confirm it arrives on the topic via the v2 stream (the message carries the v2 finding shape). Check the subscriber you rely on (see [incident-response.md](incident-response.md)) parses it.
4. Compare the mute configs: v2 mutes only apply to v2 findings.

## 3. Flip

1. Set `scc_api_version = "v2"`. The plan destroys only the v1 notification configs, v1 publisher bindings and v1 mute configs.
2. After apply, confirm findings still reach the topic, and that no v1 config remains.

## Rollback

Set `scc_api_version` back to `both` (re-creates v1 next to v2) or `v1`. Findings produced while a stream was absent are not replayed; re-list them from SCC if needed.

## Scaffolds

The scaffold default stays `v1` until the flip has been proven in a sandbox organization. Operators proving it should follow this runbook there first.
