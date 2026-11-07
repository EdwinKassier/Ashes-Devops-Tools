# System design examples: design

## Intent

A study library for **system design interviews**. Each entry is a worked answer to a common interview question, written as a deep reference. The reader can rehearse the answer out loud. When they want to, they can carry the design into this repo's Terraform.

Generic prep material stops at boxes and arrows. This library is grounded in a real landing zone. Every design says where it lives in this repo's model:
- AWS accounts and GCP projects
- the hub and spoke networks
- per-stage identities
- CMEK
- the `config/landing-zone.yaml` keys

It is shown side by side on **AWS and GCP**. This grounding is the point of the library: it lets a candidate answer the question "how would you actually build this?" with specifics.

## Audience

Engineers preparing for system design rounds: backend, platform/SRE, and data engineering. They read it like a book, rehearse from the summaries, and dip into the depth.

## Goals

- **Coverage.** The 19 walkthroughs and the primer listed below, all decided with the user.
- **Interview-shaped.** Every walkthrough follows the arc of a real interview, so the reader rehearses the shape as well as the content.
- **Correct.** Every claim that can drift (service limits, quotas, provider argument names, latency figures, pricing models) is checked against current official docs and cited inline.
- **Usable.** The two-minute answer comes first and the depth comes after. There are study aids at the end.
- **Buildable.** A "Build it here" section maps the design onto this repo, so a reader could plan it in Terraform.

## Non-goals

- Deployable or tested Terraform. The snippets are illustrative and are **not** run by `make test` or `make validate-all`.
- New reusable modules under `modules/`. Gaps are shown as raw resources (see "Build it here"), not built as modules.
- Vendor-neutral or Azure coverage. The library covers AWS and GCP only.
- Coding-round content (algorithms, data structures).

## Anti-goals (the user's own words, and what would make this a failure)

- **Overly complex.** Mitigations:
  - Each walkthrough opens with a short answer.
  - The depth is layered underneath.
  - Each walkthrough has two or three deep dives, not ten.
  - Diagrams stay legible: a Mermaid diagram should not exceed about 15 nodes. Split anything bigger.
- **Not correct.** Mitigations:
  - Every drifting fact is cited.
  - A dedicated correctness review checks each walkthrough against the docs and against this repo. The repo check covers module names, input names, config keys and root names.
  - Anything unverifiable is flagged as such, never asserted.
- **Not usable as a study guide.** Mitigations: the fixed template, the summary at the top, and the study aids. The reader can stop after any section and still have a coherent answer.

## Location and format

The library lives in `examples/system-design/`:

```
examples/system-design/
  README.md                         # index: the 19 + primer, a suggested study order, how to use the library
  00-primer.md
  01-realtime-websockets.md
  02-notification-system.md
  ...
  19-llm-serving-rag.md
```

- **Format.** One Markdown file per question. Diagrams are Mermaid fenced blocks, which render on GitHub.
- **Length.** A deep reference runs to roughly 3,000–6,000 words. The primer can be longer.
- **Links.** Relative links into the repo (modules, roots, docs) must pass `make links`, the repo's link check.
- **Existing README.** `examples/README.md`, if present, gains a pointer to the library. Otherwise the top-level README's examples section links it.

## Walkthrough template (every file follows it)

1. **The question.** The prompt exactly as an interviewer would say it, plus common variants.
2. **The two-minute answer.** A five-to-eight-sentence summary and one small diagram. This is what you would say if you only had two minutes.
3. **Clarify the requirements.** The questions to ask the interviewer. Functional and non-functional requirements, with stated assumptions (scale, latency, consistency, durability, regions).
4. **Back-of-envelope estimates.** Explicit arithmetic for QPS, bandwidth, storage, connections and fan-out, with every assumption written down. The numbers drive later choices; say which choices.
5. **API and data model.** Endpoints, events and message schemas. The key entities and their access patterns.
6. **High-level design.** A Mermaid diagram plus a walk through the request path and the write path.
7. **Deep dives.** Two or three of the hardest parts. Examples: connection fan-out, the exactly-once boundary, the hot-partition fix. For each: the alternatives considered, why the winner wins, and where it breaks.
8. **Trade-offs to defend.** A table: decision | chosen | rejected | why | what would change the answer.
9. **Failure modes and scaling limits.** What fails first as load grows ×10 and ×100, and the blast radius of each component.
10. **AWS and GCP mapping.** A side-by-side table, component by component, naming the managed service on each cloud. Call out the differences that change the design. Example: Pub/Sub topics are global, while Kinesis shards are regional and provisioned.
11. **Build it here.** See below.
12. **Runbook.** The operational procedure for the scenario's most likely serious failure, plus at most one other. The format follows the repo's runbooks: detection signal, triage, mitigation steps, verification, follow-up.
13. **Study aids.** The key numbers to memorise. The likely interviewer follow-ups, each with a crisp answer. Classic mistakes. Links to further reading.

## "Build it here" conventions

This section turns the design into this repo's terms:

- **Where it lives.** The roots and workspaces involved, for example `aws-workload-<env>`, `gcp-workload-<env>`, `aws-network` and `gcp-network-hub`. State which account or project each part sits in, and the apply order.
- **Config.** The `config/landing-zone.yaml` keys to set, as a YAML snippet using real keys from `config/landing-zone.schema.json`.
- **Existing modules.** Where a repo module covers a component, show the module call with its key inputs. The module source and input names must exist in the repo.
- **Missing modules.** Where none does, show **raw provider resources wired into the landing zone's conventions**:
  - **Naming.** Follow the repo's naming patterns for that resource class.
  - **Encryption.** CMEK/KMS on everything that supports it, using the environment's existing key from the workload stage. Never use provider-managed keys silently.
  - **Networking.** Private networking: place the resource in the correct VPC tier (public, private or data) and use private endpoints or PSC/PrivateLink. No public IPs unless the design requires them.
  - **Tags and labels.** Use the repo's required tags/labels, the ones `require_labels` enforces and `default_tags` provides.
  - **Identity.** A least-privilege service identity per component, in the repo's per-stage identity model.
  - **Gap note.** Mark the snippet with a one-line note that the repo has no module for it.
- **Scope.** Snippets are illustrative. They show the important arguments, not every one, and are labelled as such. Arguments that are shown must use current provider names (google `~> 8.0`, aws `>= 6.46, < 7.0`).

## The library

The order below is the reading order in the README index. The notes name the deep dives each walkthrough must cover; the builder picks the rest.

0. **Primer.**
   - The interview framework the template follows.
   - A back-of-envelope cheat sheet: latency numbers, throughput per instance class, storage units, availability nines to downtime.
   - An AWS↔GCP service map.
   - How this landing zone's structure anchors every design: accounts and projects, hub-spoke networking, the tiered VPC, identity, CMEK, config.
   - How to read the walkthroughs.

*Real-time and messaging*

1. **Real-time WebSocket platform** (user's #1). Millions of open connections; high-frequency client↔data traffic; chat and presence. Deep dives:
   - connection-tier scaling and the routing of a message to the right connection (pub/sub fan-out, a connection registry)
   - backpressure and slow consumers
   - reconnect storms
2. **Notification system.** Multi-channel (push, SMS, email). Deep dives: fan-out and prioritisation; retries, idempotency and dedup; user preferences and rate limits.

*Services and integration*

3. **Microservices with sync and async events** (user's #2). Deep dives:
   - choosing sync vs async per interaction
   - the transactional outbox and sagas (orchestration vs choreography)
   - idempotent consumers, schema evolution, and CQRS read models
4. **Adapter gateway over multiple backends** (user's #3). One interface over primary, backup and auxiliary instances of the same service. Examples: payment providers, LLM providers, or database replicas. Deep dives:
   - the adapter/port contract and capability negotiation
   - routing policies (priority, weighted, health-based) and circuit breakers
   - failover semantics and consistency during switchover
   - adding a new backend without client changes
5. **Rate limiter and API gateway.** Deep dives: the algorithms (token bucket, sliding window); distributed counters and their consistency; where it runs (edge, gateway or service).
6. **Payment system and ledger.** Deep dives: idempotency keys; double-entry ledger invariants; reconciliation with external providers; exactly-once boundaries.

*Read-heavy and content*

7. **URL shortener / key-value lookup.** Deep dives: ID generation; cache tiers and CDN; sharding and hot keys.
8. **News feed / timeline.** Deep dives: fan-out on write vs on read (and the hybrid for celebrities); ranking pipeline placement; cache invalidation.
9. **Video upload and streaming.** Deep dives: resumable upload; the transcoding pipeline; adaptive bitrate and CDN; cost.
10. **Search and typeahead.** Deep dives: indexing pipeline and freshness; trie vs search engine; sharding and ranking.

*Data*

11. **ETL for batch and streaming, with lineage and replay** (user's #4). Deep dives:
    - Kappa vs Lambda
    - CDC ingestion
    - replay and backfill design (immutable raw zone, offsets, idempotent writes)
    - lineage capture (OpenLineage-style)
    - late data and schema evolution
12. **Data lake and warehouse** (user's #7). Deep dives:
    - lakehouse table formats (Iceberg) vs a warehouse-native design
    - zones (raw, curated, serving) and governance
    - cost and performance: partitioning and clustering
    - access control and CMEK (the repo's VPC-SC and Lake Formation analogues)
13. **Observability platform.** Deep dives: metrics, logs and traces at scale; cardinality; sampling; retention tiers.

*Platform and resilience*

14. **N-tier network architecture** (user's #6). Presentation, application, compute and data tiers. Deep dives:
    - tier boundaries and controls (the repo's tiered VPC, firewall policy mode, security groups)
    - hub-spoke vs flat networks
    - inspected egress
    - private service access
    This walkthrough leans most heavily on the repo's existing modules.
15. **Data disaster recovery across data architectures** (user's #5). Relational, NoSQL, object storage, streams and warehouse. Deep dives:
    - RTO/RPO per tier, and the pattern ladder: backup-restore, pilot light, warm standby, active-active
    - replication modes and their consistency costs
    - DR testing and runbooks
    - the repo's backup modules and vaults
16. **Multi-region active-active global app.** Deep dives: global routing and DNS failover; data placement and residency; conflict resolution; cell-based design.
17. **Multi-tenant SaaS isolation tiers.** Deep dives: silo, pool and bridge models; noisy neighbours; per-tenant encryption; mapping tiers onto this repo's accounts and projects.
18. **Distributed job scheduler.** Deep dives: exactly-once triggering and leases; partitioning work; retries and dead letters; at-scale cron.

*AI*

19. **LLM serving and RAG system.** Deep dives:
    - inference serving: batching, GPU capacity, autoscaling, model routing (this connects to #4's adapter pattern)
    - the RAG pipeline: ingestion, chunking, vector store, freshness
    - guardrails, evaluation, and cost per token

## Correctness process (required)

- **Sources.** Every drifting fact gets an inline citation to official vendor docs (AWS, Google Cloud, HashiCorp registry), with the date checked. Vendor blogs or the Well-Architected frameworks are acceptable where the official docs are silent. Prep sites are not acceptable sources.
- **Repo references.** Every repo reference must resolve. That covers module paths, input names, config keys, root and workspace names, and runbook links.
- **Independent review.** Each walkthrough gets a review pass separate from the writer. The review checks technical correctness, the repo references, and anti-goal 1 (over-complexity).
- **Uncertainty.** Anything the writer can't verify offline is marked "verify before relying on", never stated as fact.

## Constraints

- Mermaid only, with no images. That keeps diagrams diffable and rendered on GitHub.
- `make links` must pass, along with markdownlint if the repo's meta-lint covers `examples/`.
- No secrets and no real account or project IDs in examples. Use placeholders in the repo's existing style.
- The work goes on branch `claude/system-design-examples`, cut from the PR #592 branch, and is not pushed until the user asks.

## Decided by the user

- Audience: interview prep.
- Written walkthroughs with diagrams and runbooks, not deployable code.
- The seven-part interview arc (now expanded into the template above).
- All 19 questions are kept.
- Deep reference rather than a quick read.
- It must be usable for carrying the design into the repo's Terraform.
- Missing modules are shown as raw provider resources in the landing zone's conventions.
- Anti-goals: overly complex, incorrect, unusable as a study guide.

## Calls made by the designer (the user can override)

- The location is `examples/system-design/`, with one file per question.
- Diagrams are Mermaid.
- Both clouds are shown side by side in one file, not in separate files.
- The deep-dive list per question (above).
- The 3,000–6,000 word target length.
- Snippets are illustrative and untested.
- The work goes on a separate branch.
- This design document stays in the gitignored `docs/superpowers/`, matching the repo's ignore rule.

## Resolved after the builder check (designer's calls unless marked)

- **Research and citations.** The builder has web access, so each walkthrough includes a research step:
  - Fetch the official docs for every drifting fact and cite them inline, with the date checked.
  - "Verify before relying on" is only for facts the docs genuinely don't state.
  - For provider arguments, the source of truth is the HashiCorp Registry docs for the pinned major (google `~> 8.0`, aws 6.x), plus the provider binaries already in the local plugin cache where a schema check is needed.
- **Independent review.** A fresh subagent reviews each walkthrough after it is written, and the review is a gate.
  - It checks technical correctness (spot-re-verifying at least 5 citations), the repo references, and over-complexity.
  - Findings are fixed in rounds until the review is clean.
  - A final whole-library review checks consistency across walkthroughs: the same numbers, the same conventions, and no contradictions.
- **Mechanical reference checker.** Repo references are enforced by a small script, `scripts/check-examples-refs.sh`, and not by hand.
  - It extracts `hcl` and `yaml` fences from `examples/system-design/*.md`.
  - It checks that every `source = "…/modules/…"` path exists and that every module input named in a call is declared by that module's `variables.tf`.
  - It checks every top-level config key against `config/landing-zone.schema.json`.
  - It checks every named root or workspace against `envs/` and the tfc-admin catalog.
  - It is wired into `make links`'s neighbour target and the CI meta-lint job. This is a tooling addition, not a change to `make test` or `make validate-all`.
  - Raw-resource snippets are not schema-checked; the review covers them.
- **Conventions.** The source of truth is the code, and the primer documents them once. Walkthroughs link to the primer instead of restating it.
  - **Tags and labels.** The AWS provider `default_tags` (`envs/aws/workload/providers.tf`) and GCP provider `default_labels` carry the same four keys: managed-by, landing-zone, workspace, environment. `policies/opa/require_labels.rego` enforces them.
  - **CMEK.** On AWS, the workload CMK comes from the `workload_kms_key_arn` output of `aws-workload-<env>`. On GCP, the builder locates the equivalent key output in `modules/gcp/stages/environment` / `envs/gcp/workload`.
  - **Naming.** Follow the `<prefix>-<env>-<component>` patterns used by the stage modules, derived from the code.
  - **Identity.** One service account or role per component, created in the workload root, following the pattern app-services uses for its services.
- **Partial grounding is fine.** Coverage is expected to be thin for WebSocket, notification, search, video, the data lake, observability, the scheduler and LLM serving, and most of their "Build it here" sections will be raw resources.
  - Keep "Build it here" to about 150 lines of snippets.
  - Show the novel resources and the wiring into the landing zone, not every supporting resource.
  - It need not be buildable end to end.
- **Lint.** Must pass with the repo's existing `.markdownlint.yaml`; the builder adjusts rules only if Mermaid or wide tables genuinely need it, and says so.
  - Adding Markdown under `examples/` must not disturb the count gates (`make count` and `make count-check`); check them.
  - Links may point to docs/runbooks and to modules, but never to the gitignored `docs/superpowers/`.
- **Branch.** Use `claude/system-design-examples` as is. Rebase onto `main` once PR #592 merges.

## Left to the builder

- The exact clarifying questions, the numbers, and which secondary topics to include beyond the named deep dives.
- The diagram layout.
- The batching and order of writing.
- Which runbooks to write beyond the one required per walkthrough.
