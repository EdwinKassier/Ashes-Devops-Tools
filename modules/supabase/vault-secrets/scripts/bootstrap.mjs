#!/usr/bin/env node
/**
 * Bootstrap the Supabase Vault for the target project:
 *
 *   1. Enable the `supabase_vault` extension.
 *   2. Drop the legacy public.* helpers created by earlier module versions
 *      (they were reachable through PostgREST with the anon key).
 *   3. (Re)create two SECURITY DEFINER helpers in the private, NOT
 *      API-exposed `iac_vault` schema, each with `search_path = ''` and
 *      fully-qualified references:
 *      - iac_vault.upsert_vault_secret(name, value, description)
 *      - iac_vault.delete_vault_secret(name)
 *      Both refuse any name outside the IaC namespace (^[A-Z][A-Z0-9_]*$).
 *   4. Revoke EXECUTE from PUBLIC, anon and authenticated; grant it to
 *      service_role only.
 *
 * Idempotent — safe to re-run on every apply. reconcile.mjs goes through
 * these functions (direct pg connection or the Management API — neither
 * uses PostgREST), so a successful bootstrap is its precondition.
 *
 * Runtime-managed (per-tenant, non UPPER_SNAKE_CASE) secrets are out of this
 * module's scope: an application that needs RPC access to them must ship its
 * own, separately-reviewed helpers.
 *
 * Required env: POSTGRES_URL (session-mode pooler URL is fine).
 *
 * No CLI args — all config via env so values can stay sensitive.
 */

import { Pool } from "pg";

const url = process.env.POSTGRES_URL;
if (!url) {
  console.error("[vault-secrets/bootstrap] POSTGRES_URL is not set");
  process.exit(1);
}

// Parse the URL before anything else. Fail fast with a clear message rather
// than letting new URL() throw an unhandled TypeError deep inside setup.
let _parsedUrl;
try {
  _parsedUrl = new URL(url);
} catch {
  console.error(
    "[vault-secrets/bootstrap] POSTGRES_URL is not a valid URL (cannot parse). " +
      "Check the value of POSTGRES_URL.",
  );
  process.exit(1);
}
const { hostname } = _parsedUrl;
// Hostname-based local detection — avoids false positives from '127.0.0.1'
// appearing in URL credentials or query params.
const isLocal = hostname === "127.0.0.1" || hostname === "localhost";

// TLS posture: verify the Postgres certificate by default. The bootstrap
// script installs SECURITY DEFINER helpers granted to service_role —
// running this against an attacker-controlled endpoint without TLS
// verification could let them re-route the privileged setup. Same flag
// set as reconcile.mjs, kept identical for consistency:
//   - SUPABASE_SSL_CERT: explicit base64 CA bundle (highest priority).
//     Threaded via Terraform variable (var.supabase_ssl_cert) so it is
//     always present in the local-exec environment when available.
//   - TF_VAR_supabase_ssl_cert: same cert via process.env inheritance.
//     Checked as fallback for backward compat.
//   - Supabase pooler (*.pooler.supabase.com): the pgbouncer endpoint uses
//     a self-signed TLS certificate not in CI runner CA stores. The CA
//     bundle MUST be supplied. ensureSupabaseSslCert() fetches it
//     automatically and fails fast in CI if it cannot.
//   - PGSSL_INSECURE_NO_VERIFY=1: break-glass only. Never in normal ops.
// Use || (not ??) so that an empty-string SUPABASE_SSL_CERT (e.g. when
// the Terraform variable was unset and defaulted to "") falls through to
// the TF_VAR fallback rather than being treated as a valid cert.
const sslCert =
  process.env.SUPABASE_SSL_CERT || process.env.TF_VAR_supabase_ssl_cert;
const allowInsecureTls = process.env.PGSSL_INSECURE_NO_VERIFY === "1";
const isSupabasePooler =
  hostname === "pooler.supabase.com" ||
  hostname.endsWith(".pooler.supabase.com");

if (!isLocal && isSupabasePooler && !sslCert && !allowInsecureTls) {
  console.error(
    "[vault-secrets/bootstrap] SUPABASE_SSL_CERT is required for pooler " +
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
const poolOptions = { connectionString: url, ssl, max: 1 };

// Schema that holds the IaC vault helpers. Deliberately NOT `public` and must
// never be listed in the PostgREST exposed schemas (Supabase API settings →
// "Exposed schemas" / the settings module's db_schema): PostgREST only serves
// RPCs from exposed schemas, so the anon/authenticated API keys cannot reach
// these functions over /rest/v1/rpc at all. Grants below are defence in depth.
const IAC_SCHEMA = "iac_vault";

// Name pattern of the IaC-managed namespace. Kept in lockstep with
// IAC_MANAGED_NAME in reconcile.mjs and the Terraform variable validation.
// Both helpers refuse to touch any other name, so even a caller holding
// EXECUTE cannot read-modify runtime-managed (non UPPER_SNAKE_CASE) entries.
const SQL = `
  CREATE EXTENSION IF NOT EXISTS supabase_vault;

  -- ── Migration: remove the legacy public.* helpers ─────────────────────────
  -- Earlier versions of this module created these in the API-exposed public
  -- schema. Supabase's default privileges grant EXECUTE on new public
  -- functions to anon and authenticated explicitly, and REVOKE ... FROM
  -- PUBLIC does not remove those grants — so the frontend anon key could call
  -- POST /rest/v1/rpc/upsert_vault_secret. Drop them unconditionally.
  DROP FUNCTION IF EXISTS public.upsert_vault_secret(text, text, text);
  DROP FUNCTION IF EXISTS public.delete_vault_secret(text);
  DROP FUNCTION IF EXISTS public.delete_vault_secrets_by_prefix(text);

  -- ── Private schema ────────────────────────────────────────────────────────
  CREATE SCHEMA IF NOT EXISTS ${IAC_SCHEMA};
  REVOKE ALL ON SCHEMA ${IAC_SCHEMA} FROM PUBLIC;
  REVOKE ALL ON SCHEMA ${IAC_SCHEMA} FROM anon, authenticated;
  GRANT USAGE ON SCHEMA ${IAC_SCHEMA} TO service_role;

  -- upsert_vault_secret: create or update an IaC-managed vault entry.
  -- SECURITY DEFINER with an EMPTY search_path: every object is schema-
  -- qualified, so a caller cannot shadow vault.* or operators via search_path.
  CREATE OR REPLACE FUNCTION ${IAC_SCHEMA}.upsert_vault_secret(
    secret_name text,
    secret_value text,
    secret_description text DEFAULT ''
  )
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = ''
  AS $$
  DECLARE
    existing_id uuid;
  BEGIN
    IF secret_name IS NULL OR secret_name OPERATOR(pg_catalog.!~) '^[A-Z][A-Z0-9_]*$' THEN
      RAISE EXCEPTION 'iac_vault: % is outside the IaC-managed namespace (^[A-Z][A-Z0-9_]*$)', secret_name
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT s.id INTO existing_id FROM vault.secrets AS s WHERE s.name OPERATOR(pg_catalog.=) secret_name;
    IF existing_id IS NOT NULL THEN
      PERFORM vault.update_secret(existing_id, secret_value, secret_name, secret_description);
    ELSE
      PERFORM vault.create_secret(secret_value, secret_name, secret_description);
    END IF;
  END;
  $$;

  -- delete_vault_secret: delete one IaC-managed entry (reconcile orphan
  -- sweep). Idempotent. Refuses any name outside the IaC namespace, so it
  -- cannot be used to delete runtime-managed entries.
  CREATE OR REPLACE FUNCTION ${IAC_SCHEMA}.delete_vault_secret(secret_name text)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = ''
  AS $$
  BEGIN
    IF secret_name IS NULL OR secret_name OPERATOR(pg_catalog.!~) '^[A-Z][A-Z0-9_]*$' THEN
      RAISE EXCEPTION 'iac_vault: % is outside the IaC-managed namespace (^[A-Z][A-Z0-9_]*$)', secret_name
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    DELETE FROM vault.secrets AS s WHERE s.name OPERATOR(pg_catalog.=) secret_name;
  END;
  $$;

  -- Execute: owner (the bootstrap role) and service_role only. Revoke from
  -- PUBLIC *and* from anon/authenticated explicitly, because Supabase grants
  -- those roles directly (not via PUBLIC) through default privileges.
  REVOKE ALL ON FUNCTION ${IAC_SCHEMA}.upsert_vault_secret(text, text, text) FROM PUBLIC;
  REVOKE ALL ON FUNCTION ${IAC_SCHEMA}.upsert_vault_secret(text, text, text) FROM anon, authenticated;
  GRANT EXECUTE ON FUNCTION ${IAC_SCHEMA}.upsert_vault_secret(text, text, text) TO service_role;

  REVOKE ALL ON FUNCTION ${IAC_SCHEMA}.delete_vault_secret(text) FROM PUBLIC;
  REVOKE ALL ON FUNCTION ${IAC_SCHEMA}.delete_vault_secret(text) FROM anon, authenticated;
  GRANT EXECUTE ON FUNCTION ${IAC_SCHEMA}.delete_vault_secret(text) TO service_role;
`;

// Use the Supabase Management API (SUPABASE_ACCESS_TOKEN is injected by CI) to:
//   1. Execute bootstrap SQL directly via the Management API's database/query
//      endpoint — this completely bypasses the Supavisor pooler, avoiding the
//      persistent "Tenant or user not found" error seen when connecting via
//      the pooler hostname from GitHub Actions runners.
//   2. Detect if the pooler hostname uses the wrong region and rewrite the URL
//      (kept as a fallback guard for the pg Pool path below).
//   3. Detect a paused project and trigger restore before attempting bootstrap.
const accessToken = process.env.SUPABASE_ACCESS_TOKEN;
const parsedUsername = _parsedUrl.username; // "postgres.{project_ref}" or "postgres"
const projectRef = parsedUsername.includes(".")
  ? parsedUsername.split(".").slice(1).join(".")
  : null;

// Diagnostic: log connection target (hostname, port, user — no password).
console.log(
  `[vault-secrets/bootstrap] target: ${hostname}:${_parsedUrl.port || "5432"} user=${parsedUsername || "(empty)"} projectRef=${projectRef || "(none)"}`,
);

let bootstrapComplete = false;

if (projectRef && accessToken && isSupabasePooler) {
  const mgmtBase = "https://api.supabase.com/v1";
  const headers = {
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json",
  };

  let project;
  try {
    const res = await fetch(`${mgmtBase}/projects/${projectRef}`, { headers });
    if (res.ok) {
      project = await res.json();
      console.log(
        `[vault-secrets/bootstrap] project status: ${project.status}, region: ${project.region}`,
      );
    } else {
      console.error(
        `[vault-secrets/bootstrap] Could not read project (HTTP ${res.status}). Proceeding with configured URL.`,
      );
    }
  } catch (e) {
    console.error(
      `[vault-secrets/bootstrap] Management API fetch failed: ${e.message}. Proceeding with configured URL.`,
    );
  }

  if (project) {
    // Fix region mismatch: rewrite the pooler hostname if the project's actual
    // region differs from the one in the URL. This is the primary cause of
    // "Tenant or user not found" — connecting to the wrong regional pgBouncer.
    const actualPoolerHost = `aws-0-${project.region}.pooler.supabase.com`;
    console.log(
      `[vault-secrets/bootstrap] pooler check: URL=${hostname} expected=${actualPoolerHost} match=${hostname === actualPoolerHost}`,
    );
    if (hostname !== actualPoolerHost) {
      console.log(
        `[vault-secrets/bootstrap] pooler host mismatch — URL has ${hostname}, ` +
          `project is in ${project.region}. Rewriting to ${actualPoolerHost}.`,
      );
      poolOptions.connectionString = url.replace(hostname, actualPoolerHost);
    }

    // Handle paused project.
    if (project.status === "INACTIVE" || project.status === "PAUSING") {
      console.log("[vault-secrets/bootstrap] Project is paused — requesting restore...");
      try {
        const restoreRes = await fetch(`${mgmtBase}/projects/${projectRef}/restore`, {
          method: "POST",
          headers,
        });
        if (restoreRes.ok) {
          console.log(
            "[vault-secrets/bootstrap] Restore requested. Waiting for ACTIVE_HEALTHY...",
          );
        } else {
          const body = await restoreRes.text();
          console.error(
            `[vault-secrets/bootstrap] Restore request failed (HTTP ${restoreRes.status}): ${body}. Proceeding.`,
          );
        }
      } catch (e) {
        console.error(
          `[vault-secrets/bootstrap] Restore request error: ${e.message}. Proceeding.`,
        );
      }
    }

    // Poll until ACTIVE_HEALTHY after a restore (max 8 min).
    if (
      project.status === "INACTIVE" ||
      project.status === "PAUSING" ||
      project.status === "COMING_UP"
    ) {
      const MAX_WAIT_MS = 8 * 60 * 1000;
      const POLL_INTERVAL_MS = 15_000;
      const start = Date.now();
      while (Date.now() - start < MAX_WAIT_MS) {
        await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
        try {
          const statusRes = await fetch(`${mgmtBase}/projects/${projectRef}`, { headers });
          if (statusRes.ok) {
            const p = await statusRes.json();
            console.log(`[vault-secrets/bootstrap] Project status: ${p.status}`);
            if (p.status === "ACTIVE_HEALTHY") break;
          }
        } catch {
          // transient fetch error — keep polling
        }
      }
    }

    // PRIMARY PATH: Execute bootstrap SQL via the Management API's
    // database/query endpoint. This bypasses the Supavisor pooler entirely
    // and resolves the persistent "Tenant or user not found" failure seen
    // when GitHub Actions runners connect via the pooler hostname.
    // The endpoint runs as the postgres superuser, so CREATE EXTENSION,
    // CREATE FUNCTION, REVOKE, and GRANT all work correctly.
    // Falls through to the pg Pool retry loop below on failure.
    try {
      const sqlRes = await fetch(
        `${mgmtBase}/projects/${projectRef}/database/query`,
        {
          method: "POST",
          headers,
          body: JSON.stringify({ query: SQL }),
        },
      );
      if (sqlRes.ok) {
        const body = await sqlRes.json().catch(() => null);
        // The API returns an array of rows. For DDL, it may return [] or
        // a single row. An error field in the body indicates a SQL-level
        // failure even though the HTTP status was 200.
        if (body && body.error) {
          console.error(
            `[vault-secrets/bootstrap] Management API SQL returned error: ${body.error}. Falling back to direct connection.`,
          );
        } else {
          console.log(
            `[vault-secrets/bootstrap] vault extension + ${IAC_SCHEMA}.upsert_vault_secret + ` +
              `${IAC_SCHEMA}.delete_vault_secret installed via Management API`,
          );
          bootstrapComplete = true;
        }
      } else {
        const body = await sqlRes.text().catch(() => "(unreadable)");
        console.error(
          `[vault-secrets/bootstrap] Management API SQL request failed (HTTP ${sqlRes.status}): ${body}. Falling back to direct connection.`,
        );
      }
    } catch (e) {
      console.error(
        `[vault-secrets/bootstrap] Management API SQL request error: ${e instanceof Error ? e.message : e}. Falling back to direct connection.`,
      );
    }
  }
}

// Fallback: direct pg Pool connection. Used when:
//   - No SUPABASE_ACCESS_TOKEN / projectRef (local dev, non-Supabase CI)
//   - Management API SQL path failed (endpoint unavailable, permission error)
// In CI with a Supabase pooler URL, bootstrapComplete should already be true
// from the Management API path above. This loop is the safety net.
const MAX_ATTEMPTS = 5;
const RETRY_DELAY_MS = 15_000;

for (let attempt = bootstrapComplete ? MAX_ATTEMPTS + 1 : 1; attempt <= MAX_ATTEMPTS; attempt++) {
  const pool = new Pool(poolOptions);
  try {
    await pool.query(SQL);
    console.log(
      `[vault-secrets/bootstrap] vault extension + ${IAC_SCHEMA}.upsert_vault_secret + ` +
        `${IAC_SCHEMA}.delete_vault_secret installed`,
    );
    await pool.end();
    break;
  } catch (err) {
    await pool.end();
    const msg = err instanceof Error ? err.message : String(err);
    const code = err instanceof Error ? (err.code ?? "(no code)") : "(no code)";
    const severity = err instanceof Error ? (err.severity ?? "") : "";
    const detail = err instanceof Error ? (err.detail ?? "") : "";
    const detail2 = detail ? ` detail=${detail}` : "";
    if (attempt < MAX_ATTEMPTS) {
      console.error(
        `[vault-secrets/bootstrap] attempt ${attempt}/${MAX_ATTEMPTS} failed: ${msg} (code=${code}${severity ? " severity=" + severity : ""}${detail2}). ` +
          `Retrying in ${RETRY_DELAY_MS / 1000}s...`,
      );
      await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
    } else {
      console.error(
        `[vault-secrets/bootstrap] failed after ${MAX_ATTEMPTS} attempts: ${msg} (code=${code}${severity ? " severity=" + severity : ""}${detail2})`,
      );
      process.exit(1);
    }
  }
}
