#!/usr/bin/env node
/**
 * Reconcile the Supabase Vault contents against a desired-state map.
 *
 * Invoked by the vault-secrets Terraform module's null_resource.reconcile
 * provisioner once per apply. Idempotent. Handles add/update/remove in
 * one pass — no destroy provisioner, no per-secret resource lifecycle.
 *
 * Required env:
 *   POSTGRES_URL          — direct/session-pooler connection
 *   VAULT_DESIRED_JSON    — JSON string: { "<NAME>": "<value>", ... }
 *                           Empty values are treated as "do not store"
 *                           (and any existing entry with that name is
 *                           deleted, matching add/remove semantics).
 *   VAULT_ALLOW_EMPTY_DESIRED  — opt-in escape hatch: when "1", allow
 *                                a deploy to wipe the vault even though
 *                                desired is empty. Default off; the
 *                                safety guard refuses to proceed in
 *                                that case to prevent accidental data
 *                                loss on first-deploy or after a
 *                                workflow-edit regression.
 *
 * Algorithm:
 *   1. Parse desired = JSON.parse(VAULT_DESIRED_JSON), strip empty values.
 *   2. SELECT name FROM vault.secrets → existing names. Filter to
 *      IaC-managed (UPPER_SNAKE_CASE); runtime entries (per-tenant
 *      tokens, etc.) are out of this script's scope and must not be
 *      touched.
 *   3. SAFETY GUARD: refuse to delete every existing entry when
 *      desired is empty (see `VAULT_ALLOW_EMPTY_DESIRED` above).
 *   4. For each desired entry: upsert via public.upsert_vault_secret.
 *   5. For each existing IaC-managed name NOT in desired: delete via
 *      public.delete_vault_secret(name) — one row per call. Same SQL
 *      function the runtime API uses, so reconcile and app code share
 *      one write path.
 *
 * Concurrency: GitHub Actions concurrency groups (terraform-{env}) prevent
 * simultaneous applies into the same DB, so step 2-5 doesn't race. If you
 * ever lift that, wrap the whole thing in a serializable transaction.
 */

import { Pool } from "pg";

const url = process.env.POSTGRES_URL;
const desiredJson = process.env.VAULT_DESIRED_JSON ?? "{}";

if (!url) {
  console.error("[vault-secrets/reconcile] POSTGRES_URL is not set");
  process.exit(1);
}

let desired;
try {
  desired = JSON.parse(desiredJson);
} catch (err) {
  console.error(
    "[vault-secrets/reconcile] VAULT_DESIRED_JSON is not valid JSON:",
    err instanceof Error ? err.message : err,
  );
  process.exit(1);
}

if (typeof desired !== "object" || desired === null || Array.isArray(desired)) {
  console.error(
    "[vault-secrets/reconcile] VAULT_DESIRED_JSON must be a JSON object of name → value",
  );
  process.exit(1);
}

// Reconcile only manages the IaC namespace: UPPER_SNAKE_CASE names.
// Anything else (lowercase, kebab-case, mixed) is reserved for runtime-
// managed entries — e.g., per-tenant OAuth tokens that the app writes
// via setVaultSecret() / deleteVaultSecret(). The orphan-delete sweep
// MUST NOT touch runtime entries, otherwise the next deploy after a
// tenant connects an integration would wipe their token.
const IAC_MANAGED_NAME = /^[A-Z][A-Z0-9_]*$/;

// Validate desired keys BEFORE computing desiredEntries / desiredNames.
//
// Why this is critical: if an invalid key (e.g., `bad-name`) slipped
// into desiredNames, it would (a) make desiredEntries non-empty and
// thereby bypass the empty-set safety guard below, and (b) never
// match any real UPPER_SNAKE_CASE name in the orphan-delete loop —
// causing every legitimate IaC-managed vault entry to be marked an
// orphan and deleted. We refuse to apply when any non-empty desired
// key violates UPPER_SNAKE_CASE; the operator must fix the GitHub
// secret name and redeploy. The extract step (extract-vault-secrets.mjs)
// also filters/warns on bad names, so a violation reaching this point
// usually means a manual `pnpm iac:deploy` with a hand-built map.
// Helper: a desired entry is "present" iff its value is a non-empty,
// non-whitespace-only string. Matches the empty-as-missing semantics of
// extract-vault-secrets.mjs (which trims before checking emptiness) — a
// secret value of "   " in a manually-supplied VAULT_DESIRED_JSON must
// be treated identically to an absent value, otherwise it would slip
// past the empty-desired safety guard while contributing nothing real.
const hasValue = (value) =>
  typeof value === "string" && value.trim().length > 0;

const invalidNames = [];
for (const [name, value] of Object.entries(desired)) {
  if (!hasValue(value)) {continue;} // strip empty / whitespace-only
  if (!IAC_MANAGED_NAME.test(name)) {
    invalidNames.push(name);
  }
}
if (invalidNames.length > 0) {
  console.error(
    "[vault-secrets/reconcile] REFUSING to apply: invalid VAULT_* secret name(s):\n" +
      invalidNames.map((n) => "    - " + n).join("\n") +
      "\n\n  Names must be UPPER_SNAKE_CASE (^[A-Z][A-Z0-9_]*$).\n" +
      "  Fix the GitHub environment secret(s) and redeploy.\n" +
      "  See docs/development/guides/adding-vault-secret.md.",
  );
  process.exit(1);
}

// Strip empty / whitespace-only values — an absent or blank GitHub
// secret should result in the entry being missing from the vault, not
// stored as "" or "   ". Names are already validated above, so this
// filter is purely about empty values. Uses the same `hasValue` helper
// as the validation loop so the "present" semantic stays in lockstep.
const desiredEntries = Object.entries(desired).filter(([, v]) => hasValue(v));
const desiredNames = new Set(desiredEntries.map(([k]) => k));

// Parse the URL before anything else. Fail fast with a clear message rather
// than letting new URL() throw an unhandled TypeError deep inside reconcile.
let _parsedUrl;
try {
  _parsedUrl = new URL(url);
} catch {
  console.error(
    "[vault-secrets/reconcile] POSTGRES_URL is not a valid URL (cannot parse). " +
      "Check the value of POSTGRES_URL.",
  );
  process.exit(1);
}
const { hostname } = _parsedUrl;
// Hostname-based local detection — avoids false positives from '127.0.0.1'
// appearing in URL credentials or query params.
const isLocal = hostname === "127.0.0.1" || hostname === "localhost";

// TLS posture: verify the Postgres certificate by default. This pool
// performs privileged vault writes (service-role) over a public network
// in CI, so a misrouted endpoint or hijacked DNS without verification
// would let an attacker rewrite or exfiltrate every secret.
//
//   - Local (127.0.0.1 / localhost): no SSL — Supabase's local pooler
//     doesn't use TLS.
//   - Remote with SUPABASE_SSL_CERT set: validate against the supplied
//     CA bundle (full verification, preferred when the cert is available).
//   - Supabase pooler (*.pooler.supabase.com) without SUPABASE_SSL_CERT:
//     fail fast — the CA bundle MUST be supplied for pooler connections.
//     ensureSupabaseSslCert() fetches it automatically and fails fast in
//     CI if it cannot reach the pooler endpoint.
//   - Other remote without SUPABASE_SSL_CERT: validate against the system
//     trust store (rejectUnauthorized: true).
//   - Break-glass: PGSSL_INSECURE_NO_VERIFY=1 disables verification for
//     incident-recovery runs. Loud-by-design env var name; never set in
//     normal operation.
//
// SUPABASE_SSL_CERT: explicit base64 CA bundle (highest priority).
//   Threaded via Terraform variable (var.supabase_ssl_cert) so it is
//   always present in the local-exec environment when available.
// TF_VAR_supabase_ssl_cert: same cert via process.env inheritance.
//   Checked as fallback for backward compat.
//
// Use || (not ??) so that an empty-string SUPABASE_SSL_CERT (e.g. when
// the Terraform variable defaulted to "") falls through to the TF_VAR
// fallback rather than being treated as a valid cert.
const sslCert =
  process.env.SUPABASE_SSL_CERT || process.env.TF_VAR_supabase_ssl_cert;
const allowInsecureTls = process.env.PGSSL_INSECURE_NO_VERIFY === "1";
const isSupabasePooler =
  hostname === "pooler.supabase.com" ||
  hostname.endsWith(".pooler.supabase.com");

if (!isLocal && isSupabasePooler && !sslCert && !allowInsecureTls) {
  console.error(
    "[vault-secrets/reconcile] SUPABASE_SSL_CERT is required for pooler " +
      "connections but is not set. ensureSupabaseSslCert() should have fetched " +
      "it automatically — check that TF_VAR_region is correct and the pooler " +
      "endpoint is reachable from CI. Set PGSSL_INSECURE_NO_VERIFY=1 only for " +
      "break-glass recovery.",
  );
  process.exit(1);
}

const ssl = isLocal
  ? undefined
  : {
      rejectUnauthorized: !allowInsecureTls,
      ...(sslCert && {
        ca: Buffer.from(sslCert, "base64").toString("utf-8"),
      }),
    };

// Use the Supabase Management API (SUPABASE_ACCESS_TOKEN is injected by CI)
// as the primary path for reconcile operations. This bypasses the Supavisor
// pooler entirely, avoiding the "Tenant or user not found" error that persists
// on GitHub Actions runners. Falls back to pg Pool when the Management API is
// not available (local dev, non-Supabase CI environments).
//
// SQL escaping for Management API calls: names are UPPER_SNAKE_CASE (no SQL
// special characters). Values use dollar-quoting with a tag that cannot appear
// in typical credentials/API keys. If the tag IS found in a value, we fall
// back to single-quote escaping with ' → ''.
const accessToken = process.env.SUPABASE_ACCESS_TOKEN;
const parsedUsername = _parsedUrl.username;
const projectRef = parsedUsername.includes(".")
  ? parsedUsername.split(".").slice(1).join(".")
  : null;

const MGMT_BASE = "https://api.supabase.com/v1";

async function mgmtQuery(ref, token, sql) {
  const res = await fetch(`${MGMT_BASE}/projects/${ref}/database/query`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ query: sql }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "(unreadable)");
    throw new Error(`HTTP ${res.status}: ${body}`);
  }
  const data = await res.json();
  if (data && data.error) {throw new Error(`SQL error: ${data.error}`);}
  return data ?? [];
}

// SQL literal quoting for vault secret values. Names are UPPER_SNAKE_CASE
// and need no escaping. Values may contain arbitrary characters.
function sqlLiteral(str) {
  const tag = "$_v_$";
  if (!str.includes(tag)) {return tag + str + tag;}
  // Fallback: standard single-quote escaping (PostgreSQL standard_conforming_strings=on)
  return "'" + str.replace(/'/g, "''") + "'";
}

let upserted = 0;
let deleted = 0;
let reconcileComplete = false;

if (projectRef && accessToken && isSupabasePooler) {
  try {
    // Log project status for diagnostics (region, active status).
    const projectRes = await fetch(`${MGMT_BASE}/projects/${projectRef}`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (projectRes.ok) {
      const project = await projectRes.json();
      console.log(
        `[vault-secrets/reconcile] project status: ${project.status}, region: ${project.region}`,
      );
    }

    // 1. Read existing IaC-managed names from vault.
    const rows = await mgmtQuery(
      projectRef,
      accessToken,
      "SELECT name FROM vault.secrets WHERE name IS NOT NULL",
    );
    const existing = new Set(
      (rows || []).map((r) => r.name).filter((n) => IAC_MANAGED_NAME.test(n)),
    );

    // 1a. SAFETY GUARD: refuse to wipe a non-empty vault when desired is empty.
    if (desiredEntries.length === 0 && existing.size > 0) {
      if (process.env.VAULT_ALLOW_EMPTY_DESIRED !== "1") {
        console.error(
          "[vault-secrets/reconcile] REFUSING to delete all existing vault entries.\n" +
            "  Desired set is empty, but the vault contains " +
            existing.size +
            " entry/entries:\n" +
            [...existing].map((n) => "    - " + n).join("\n") +
            "\n\n" +
            "  This usually means VAULT_*-prefixed GitHub environment\n" +
            "  secrets are not yet populated for this environment.\n" +
            "  Add them in repo Settings → Environments before deploying.\n\n" +
            "  If you really want to wipe the vault, set\n" +
            "  VAULT_ALLOW_EMPTY_DESIRED=1 in the apply environment.",
        );
        process.exit(1);
      }
      console.warn(
        "[vault-secrets/reconcile] VAULT_ALLOW_EMPTY_DESIRED=1 — proceeding to clear " +
          existing.size +
          " entry/entries.",
      );
    }

    // 2. Upsert desired entries.
    for (const [name, value] of desiredEntries) {
      await mgmtQuery(
        projectRef,
        accessToken,
        `SELECT public.upsert_vault_secret(${sqlLiteral(name)}, ${sqlLiteral(value)}, 'Managed by Terraform vault-secrets module')`,
      );
      console.log(`[vault-secrets/reconcile] ${name}: upserted`);
      upserted++;
    }

    // 3. Delete orphans.
    for (const name of existing) {
      if (!desiredNames.has(name)) {
        await mgmtQuery(
          projectRef,
          accessToken,
          `SELECT public.delete_vault_secret(${sqlLiteral(name)})`,
        );
        console.log(`[vault-secrets/reconcile] ${name}: deleted (orphan)`);
        deleted++;
      }
    }

    console.log(
      `[vault-secrets/reconcile] done: ${upserted} upserted, ${deleted} deleted`,
    );
    reconcileComplete = true;
  } catch (err) {
    console.error(
      "[vault-secrets/reconcile] Management API path failed:",
      err instanceof Error ? err.message : err,
      "— falling back to direct connection.",
    );
  }
}

if (reconcileComplete) {
  process.exit(0);
}

// Fallback: direct pg Pool connection. Used when Management API path is
// unavailable or failed (local dev, non-Supabase CI, permission issues).
let connectionString = url;
if (isSupabasePooler && projectRef && accessToken) {
  // Re-check region mismatch for the pg Pool fallback path.
  try {
    const res = await fetch(`${MGMT_BASE}/projects/${projectRef}`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (res.ok) {
      const project = await res.json();
      const actualPoolerHost = `aws-0-${project.region}.pooler.supabase.com`;
      if (hostname !== actualPoolerHost) {
        console.log(
          `[vault-secrets/reconcile] pooler host mismatch (${hostname} → ${actualPoolerHost}). Rewriting URL.`,
        );
        connectionString = url.replace(hostname, actualPoolerHost);
      }
    }
  } catch {
    // ignore — proceed with original URL
  }
}

const pool = new Pool({
  connectionString,
  ssl,
  max: 1,
});

try {
  // 1. Read existing names so we can compute orphans.
  // Filter to IaC-managed names only — runtime-managed entries (per-tenant
  // tokens, etc.) are out of this script's scope and must not be touched.
  const { rows } = await pool.query(
    "SELECT name FROM vault.secrets WHERE name IS NOT NULL",
  );
  const existing = new Set(
    rows.map((r) => r.name).filter((n) => IAC_MANAGED_NAME.test(n)),
  );

  // 1a. SAFETY GUARD: refuse to wipe a non-empty vault when the desired
  // set is empty. This catches:
  //   - First deploy of this branch, where no VAULT_* secrets are
  //     populated yet but vault.secrets has entries from previous
  //     deploys (would otherwise silently delete everything).
  //   - A workflow edit that accidentally removes the extract step
  //     (TF_VAR_vault_secrets defaults to {}, reconcile sees empty
  //     desired, would otherwise silently wipe the vault).
  //
  // To intentionally clear the vault, set VAULT_ALLOW_EMPTY_DESIRED=1
  // in the environment running terraform apply.
  if (desiredEntries.length === 0 && existing.size > 0) {
    if (process.env.VAULT_ALLOW_EMPTY_DESIRED !== "1") {
      console.error(
        "[vault-secrets/reconcile] REFUSING to delete all existing vault entries.\n" +
          "  Desired set is empty, but the vault contains " +
          existing.size +
          " entry/entries:\n" +
          [...existing].map((n) => "    - " + n).join("\n") +
          "\n\n" +
          "  This usually means VAULT_*-prefixed GitHub environment\n" +
          "  secrets are not yet populated for this environment.\n" +
          "  Add them in repo Settings → Environments before deploying.\n\n" +
          "  If you really want to wipe the vault, set\n" +
          "  VAULT_ALLOW_EMPTY_DESIRED=1 in the apply environment.",
      );
      await pool.end();
      process.exit(1);
    }
    console.warn(
      "[vault-secrets/reconcile] VAULT_ALLOW_EMPTY_DESIRED=1 — proceeding to clear " +
        existing.size +
        " entry/entries.",
    );
  }

  // 2. Upsert each desired entry. Names are already validated as
  // UPPER_SNAKE_CASE above (invalid names cause the script to exit
  // before reaching this loop), so no per-entry name check is needed.
  for (const [name, value] of desiredEntries) {
    await pool.query(
      "SELECT public.upsert_vault_secret($1::text, $2::text, $3::text)",
      [name, value, "Managed by Terraform vault-secrets module"],
    );
    console.log(`[vault-secrets/reconcile] ${name}: upserted`);
    upserted++;
  }

  // 3. Delete orphans — IaC-managed names in the vault that aren't in the
  // desired set. Goes through public.delete_vault_secret so runtime and
  // IaC use the same write path. This is what makes "remove a VAULT_*
  // GitHub secret → it disappears from the vault on next deploy" work.
  // Runtime-managed entries (lowercase names) were filtered out of
  // `existing` above and are untouched.
  for (const name of existing) {
    if (!desiredNames.has(name)) {
      await pool.query("SELECT public.delete_vault_secret($1::text)", [name]);
      console.log(`[vault-secrets/reconcile] ${name}: deleted (orphan)`);
      deleted++;
    }
  }

  console.log(
    `[vault-secrets/reconcile] done: ${upserted} upserted, ${deleted} deleted`,
  );
} catch (err) {
  console.error(
    "[vault-secrets/reconcile] failed:",
    err instanceof Error ? err.message : err,
  );
  await pool.end();
  process.exit(1);
}

await pool.end();
