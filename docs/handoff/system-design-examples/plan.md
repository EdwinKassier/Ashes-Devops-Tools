# System Design Examples Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `examples/system-design/`, a study library of 19 deep-reference system-design interview walkthroughs plus a primer. Each walkthrough is grounded in this landing zone, shown on AWS and GCP side by side, and comes with diagrams and runbooks.

**Architecture:**
- **Content:** one Markdown file per question, all following one fixed 13-section template, with Mermaid diagrams.
- **Guard script:** checks that every repo reference in the snippets resolves, and runs in `make` and in CI.
- **Primer:** written first and owns the shared conventions and numbers. Every walkthrough links to it instead of restating them.

**Tech Stack:** Markdown, Mermaid, bash, `jq`, Python 3 (repo's existing `check-md-links.py`), GitHub Actions meta-lint job.

**Spec:** `docs/superpowers/specs/2026-11-07-system-design-examples-design.md`. This is the binding authority; read it fully. Its "Walkthrough template", "Build it here conventions", "The library", "Correctness process" and "Resolved after the builder check" sections are requirements for every content task.

## Global Constraints

- **Location:** every content file lives in `examples/system-design/`. File names are `NN-<slug>.md`, where NN is the spec's library number zero-padded (`00-primer.md` … `19-llm-serving-rag.md`).
- **Template:** every walkthrough has the 13 template sections, in order, as `##` headings with exactly these titles:
  - `The question`
  - `The two-minute answer`
  - `Clarify the requirements`
  - `Back-of-envelope estimates`
  - `API and data model`
  - `High-level design`
  - `Deep dives`
  - `Trade-offs to defend`
  - `Failure modes and scaling limits`
  - `AWS and GCP mapping`
  - `Build it here`
  - `Runbook`
  - `Study aids`
- **Length:** 3,000–6,000 words per walkthrough. The primer is exempt.
- **Diagrams:** Mermaid only, no images, and at most 15 nodes per diagram.
- **Cloud coverage:** AWS and GCP appear side by side in the same file.
- **Citations:** every drifting fact (service limit, quota, provider argument, latency or throughput figure, pricing model) carries an inline link to official docs with a `(checked 2026-11)` marker. Facts the docs don't state are marked **verify before relying on**.
- **Snippet pins:** snippets use google `~> 8.0` and aws `>= 6.46.0, < 7.0.0` argument names. Fence HCL as `hcl` and config as `yaml`.
- **"Build it here" length:** at most about 150 lines of snippets.
- **Raw resources** follow the primer's conventions section: naming, CMEK, VPC tier, the four tags/labels, and a per-component identity.
- **Placeholders:** no real account IDs, project IDs or secrets. Use placeholders in the repo's existing style.
- **Gates:** `make links`, `make examples-refs` (Task 1), markdownlint via pre-commit, `make count-check` and `make consistency` stay green.
- **Commits:** one per task. Conventional message `docs(examples): <walkthrough title>`. Use `git commit --no-verify` (user-authorised for this repo's legacy hook) with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.

## Review Focus

1. **A repo reference that doesn't exist.** A reader copies a `source`, input name or config key into Terraform and the plan fails. Task 1's checker must fail the build for any of these.
2. **Contradictory numbers across walkthroughs.** For example, connections per node in #1 vs #16. The primer owns shared numbers and walkthroughs cite it; the final review (Task 22) checks this across the library.
3. **Stale or invented service limits.** These undermine trust in the whole guide. Each content task's review re-fetches at least five of its citations.
4. **A "Build it here" that silently drops the conventions.** Examples: a public bucket, a provider-managed key, missing labels. The per-task review checks every raw snippet against the primer's conventions list.
5. **Depth that hides the answer.** The two-minute answer must stand alone. The per-task review reads only that section and judges whether it would pass an interview opener.

---

### Task 1: Reference checker for the examples library

**Files:**
- Create: `scripts/check-examples-refs.sh`
- Create: `scripts/tests/test-check-examples-refs.sh`, with fixtures under `scripts/tests/fixtures/examples-refs/`
- Modify: `Makefile` (new target `examples-refs`, added to `ci`)
- Modify: `.github/workflows/terraform-plan.yml` (meta-lint job: one step after the links step)

**Interfaces:**
- Produces: `bash scripts/check-examples-refs.sh [dir]`. The default `dir` is `examples/system-design`. It exits 0 when clean, and exits 1 with one line per broken reference: `file:line: <kind> <ref> not found`.

The script checks every ```` ```hcl ```` and ```` ```yaml ```` fence in `*.md` under `dir`:
- `source = "<relative path>"` resolves to an existing directory under `modules/`. The relative path is resolved from the repo root: strip any leading `../`, then require a `modules/` prefix.
- Inside a `module` block whose source resolved, every argument name (`name =` at the block's top indentation, excluding meta-arguments `source`, `count`, `for_each`, `providers` and `depends_on`) is declared as `variable "<name>"` in that module's `*.tf`.
- In `yaml` fences, every top-level key path (the first two levels, e.g. `aws.network`, `gcp.environments`) exists as a property path in `config/landing-zone.schema.json`. Read the schema with `jq`.
- Any backticked `envs/<path>` in prose or fences resolves to an existing directory.
- Raw `resource` blocks are not checked.

- [ ] **Step 1: Write the failing test.** `test-check-examples-refs.sh` follows the style of the existing `scripts/tests/test-*.sh` files (plain bash with `ok`/`fail` counters), using a temp dir of fixture Markdown files.
  - **Should pass:** a fixture citing `modules/gcp/network/tiered-vpc` with a real input such as `subnet_cidrs`, the YAML key `gcp.network`, and `envs/gcp/workload`.
  - **Should fail on:** a nonexistent module path, a nonexistent input on a real module, a nonexistent YAML key, and a nonexistent `envs/` path. Each failure line names the file and line.
- [ ] **Step 2: Run it.** `bash scripts/tests/test-check-examples-refs.sh` should fail because the script is missing.
- [ ] **Step 3: Implement** `scripts/check-examples-refs.sh`. Write it to shellcheck-clean bash; use `awk` for fence extraction and `jq` for the schema. An empty or missing `dir` passes.
- [ ] **Step 4: Run** the test, then `make shellcheck` (if shellcheck is installed). Expected: PASS.
- [ ] **Step 5: Wire it up.**
  - Add a Makefile target `examples-refs` with a `##` help text, and append it to the `ci` target's sequence.
  - Add a CI meta-lint step `Check examples references` running `bash scripts/check-examples-refs.sh` after the step that runs `scripts/check-md-links.py`.
  - Run `make examples-refs`. With no library yet it should pass.
- [ ] **Step 6: Commit** `feat(ci): check repo references in the system-design examples`.

### Task 2: Library index and primer

**Files:**
- Create: `examples/system-design/README.md`, `examples/system-design/00-primer.md`
- Create: `examples/README.md`. It is a short index of every subfolder of `examples/`, one line each, with `system-design/` listed first.
- Modify: `README.md`. In the section that lists examples, add a one-line pointer to `examples/system-design/`.

**Interfaces:**
- Produces anchors that walkthroughs link to: `00-primer.md#conventions`, `#estimation-cheat-sheet`, `#aws-gcp-service-map` and `#how-this-landing-zone-anchors-a-design`. Walkthroughs link to these anchors and never restate their content.

**`README.md`:**
- the purpose (interview prep grounded in this landing zone)
- how to use the library (two-minute answer first, then the depth)
- the 19 + primer in the spec's reading order, grouped as in the spec, with a one-line hook each
- the template's 13 sections listed once

**`00-primer.md` sections:**
- **Interview framework.** The template's arc and why each step exists, with timing for a 45-minute round.
- **Estimation cheat sheet.** Latency numbers, per-instance throughput rules of thumb, storage units, nines to downtime per year and month, plus common QPS conversions. Cite sources.
- **AWS–GCP service map.** A table covering compute, containers, serverless, LB/edge, CDN, DNS, queues/streams, pub/sub, workflow, relational, global relational, KV/NoSQL, wide-column, cache, object storage, warehouse, lake/table formats, ETL/streaming processing, search, vector, observability, KMS, secrets, identity, networking (hub, transit, private access), and backup/DR. Name a primary service per cell and cite each cell's official product page.
- **How this landing zone anchors a design.**
  - accounts/projects per layer and per environment (`docs/architecture/aws-landing-zone.md`, `gcp-landing-zone.md`)
  - hub-spoke and the tiered VPC (public/private/database)
  - inspected egress
  - per-stage identities
  - CMEK
  - `config/landing-zone.yaml`
  - typed contracts between roots
  Link each to its doc or module.
- **Conventions.** Derive these from the code and cite the file for each.
  - **Naming patterns:** take them from the stage modules.
  - **Tags and labels:** the four keys. AWS `default_tags` is in `envs/aws/workload/providers.tf`. GCP `default_labels` is in `envs/gcp/workload/providers.tf`. Both are enforced by `policies/opa/require_labels.rego`.
  - **CMEK source:** on AWS, the `workload_kms_key_arn` output of `aws-workload-<env>`. On GCP, find the equivalent key output in `envs/gcp/workload` / `modules/gcp/stages/environment` and name it exactly. If none exists, say which key the walkthroughs should use and flag it.
  - **VPC-tier placement rules.**
  - **Private-access rules:** PrivateLink/PSC, no public IPs by default.
  - **Per-component identity:** follow `modules/gcp/stages/app-services` and `modules/aws/stages/app-services`.
  - **A canonical raw-resource snippet on each cloud** that shows all of the above.
- **How to read a walkthrough.**

- [ ] **Step 1:** Research and write both files. Every service-map cell and cheat-sheet number is cited.
- [ ] **Step 2:** Run `make links examples-refs`, and run markdownlint with `pre-commit run markdownlint --files examples/system-design/*.md examples/README.md README.md` if pre-commit is available, otherwise `npx markdownlint-cli2`. Also run `make count-check`. Expected: all pass.
- [ ] **Step 3:** Commit `docs(examples): system-design library index and primer`.

### Tasks 3–21: One walkthrough each

Each task produces exactly one file and follows the spec's template, conventions and correctness process. The spec's numbered "The library" entry for that question lists the deep dives that must appear. Before writing, the implementer reads `00-primer.md` and links to its anchors.

**Steps, identical for every walkthrough task:**
- [ ] **Step 1: Research.** Collect official-doc citations for every limit, quota and argument the design relies on, on both clouds. Look up which repo modules, roots and config keys cover each component (`ls modules`, the module `variables.tf` files, `config/landing-zone.schema.json`).
- [ ] **Step 2: Write** the walkthrough: the 13 sections, 3,000–6,000 words, Mermaid diagrams of at most 15 nodes, the cited facts, and the side-by-side AWS/GCP mapping. "Build it here" uses module calls where modules exist and convention-following raw resources where they don't, each raw snippet with a one-line gap note, at most about 150 lines in total. The runbook follows the format of `docs/runbooks/*.md`: detection, triage, mitigation, verification, follow-up.
- [ ] **Step 3: Verify.** Run `make links examples-refs`, markdownlint on the file, and a word count (`wc -w`, which must be within 3,000–6,000), then check the section headings with `grep -c '^## '` against the 13 titles. Expected: all pass.
- [ ] **Step 4: Commit** `docs(examples): <title>`.

| Task | File | Title |
|---|---|---|
| 3 | `01-realtime-websockets.md` | Real-time WebSocket platform |
| 4 | `02-notification-system.md` | Notification system |
| 5 | `03-microservices-sync-async.md` | Microservices with sync and async events |
| 6 | `04-adapter-gateway.md` | Adapter gateway over multiple backends |
| 7 | `05-rate-limiter-api-gateway.md` | Rate limiter and API gateway |
| 8 | `06-payment-ledger.md` | Payment system and ledger |
| 9 | `07-url-shortener-kv.md` | URL shortener / key-value lookup |
| 10 | `08-news-feed.md` | News feed / timeline |
| 11 | `09-video-upload-streaming.md` | Video upload and streaming |
| 12 | `10-search-typeahead.md` | Search and typeahead |
| 13 | `11-etl-batch-streaming.md` | ETL for batch and streaming, with lineage and replay |
| 14 | `12-data-lake-warehouse.md` | Data lake and warehouse |
| 15 | `13-observability-platform.md` | Observability platform |
| 16 | `14-n-tier-network.md` | N-tier network architecture |
| 17 | `15-data-disaster-recovery.md` | Data disaster recovery across data architectures |
| 18 | `16-multi-region-active-active.md` | Multi-region active-active global app |
| 19 | `17-multi-tenant-saas.md` | Multi-tenant SaaS isolation tiers |
| 20 | `18-distributed-job-scheduler.md` | Distributed job scheduler |
| 21 | `19-llm-serving-rag.md` | LLM serving and RAG system |

**Cross-references to keep consistent:**
- #19's model routing links to #4's adapter pattern.
- #15's DR ladder links to #16 for active-active.
- #11 and #12 share the raw/curated/serving zone names; #12 defines them and #11 cites #12.
- #3's outbox is cited by #6 and #18.
- #14 is the reference for VPC-tier placement that every other "Build it here" links to.

Where a later task depends on an earlier file's terminology, the earlier file's terms win.

### Task 22: Library-wide consistency and link pass

**Files:**
- Modify: whatever the checks below flag, under `examples/system-design/`.

- [ ] **Step 1:** Check consistency across the whole library:
  - Every shared number appears once in the primer and is cited elsewhere, not re-derived with different values.
  - The zone names, conventions and service-map choices match the primer.
  - The cross-references listed above exist and point at real anchors.
  - Every README index entry links to an existing file whose title matches.
- [ ] **Step 2:** Run `make links examples-refs count-check consistency`, markdownlint on `examples/**/*.md`, and `bash scripts/tests/test-check-examples-refs.sh`. Expected: all pass.
- [ ] **Step 3:** Commit `docs(examples): cross-library consistency pass`, if anything changed.
