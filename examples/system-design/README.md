# System design examples

Worked answers to nineteen common system design interview questions, plus a
primer. Each one is written as a deep reference you can rehearse out loud, and
each one is grounded in this repository's AWS and GCP landing zone.

Generic interview prep stops at boxes and arrows. These walkthroughs go one step
further and answer the follow-up "how would you actually build this?": which AWS
account or GCP project a component lives in, which subnet tier, which identity,
which encryption key, and which `config/landing-zone.yaml` keys you would set.
AWS and GCP sit side by side in every file.

The snippets are illustrative. They are not applied, and `make test` and
`make validate-all` do not run them.

## How to use this library

1. **Read the [primer](00-primer.md) first.** It holds the interview framework,
   the estimation cheat sheet, the AWS-GCP service map and the landing-zone
   conventions. The walkthroughs link to it rather than repeating it.
2. **Start each walkthrough with "The two-minute answer".** Say it out loud. If
   you can give it without notes, you can survive the first ten minutes of the
   real round.
3. **Then go deep, one section at a time.** Every section stands on its own, so
   you can stop after any of them and still have a coherent answer.
4. **Finish with "Study aids".** It lists the numbers to memorise, the likely
   follow-up questions with crisp answers, and the classic mistakes.
5. **Carry it into Terraform when you want to.** "Build it here" maps the design
   onto this repo's roots, modules and config keys.

## The walkthrough template

Every walkthrough uses the same thirteen sections, in this order:

1. The question
2. The two-minute answer
3. Clarify the requirements
4. Back-of-envelope estimates
5. API and data model
6. High-level design
7. Deep dives
8. Trade-offs to defend
9. Failure modes and scaling limits
10. AWS and GCP mapping
11. Build it here
12. Runbook
13. Study aids

The [primer](00-primer.md#how-to-read-a-walkthrough) explains what each section
is for and how long to spend on it in a 45-minute round.

## Reading order

Read in this order the first time through. Later walkthroughs reuse ideas from
earlier ones: the outbox pattern from #3, the adapter pattern from #4, the data
zones and the VPC-tier rules from the primer.

### Primer

- [**Primer**](00-primer.md): the interview framework, the estimation cheat
  sheet, the AWS-GCP service map, and how this landing zone anchors a design.

### Real-time and messaging

- **#1 Real-time WebSocket platform** (`01-realtime-websockets.md`). Millions of
  open connections, chat and presence: route each message to the right socket,
  and survive slow consumers and reconnect storms.
- **#2 Notification system** (`02-notification-system.md`). Push, SMS and email
  from one pipeline, with prioritised fan-out, idempotent retries, and
  per-user preferences and rate limits.

### Services and integration

- **#3 Microservices with sync and async events** (`03-microservices-sync-async.md`).
  When to call and when to publish, the transactional outbox, sagas,
  idempotent consumers and CQRS read models.
- **#4 Adapter gateway over multiple backends** (`04-adapter-gateway.md`). One
  interface over primary, backup and auxiliary providers, with routing
  policies, circuit breakers and safe failover.
- **#5 Rate limiter and API gateway** (`05-rate-limiter-api-gateway.md`). Token
  bucket against sliding window, distributed counters, and whether the limit
  lives at the edge, the gateway or the service.
- **#6 Payment system and ledger** (`06-payment-ledger.md`). Idempotency keys,
  double-entry invariants, reconciliation with providers, and where
  exactly-once really holds.

### Read-heavy and content

- **#7 URL shortener / key-value lookup** (`07-url-shortener-kv.md`). ID
  generation, cache tiers and CDN, sharding and hot keys.
- **#8 News feed / timeline** (`08-news-feed.md`). Fan-out on write against
  fan-out on read, the celebrity hybrid, ranking and cache invalidation.
- **#9 Video upload and streaming** (`09-video-upload-streaming.md`). Resumable
  upload, the transcoding pipeline, adaptive bitrate over a CDN, and what it
  all costs.
- **#10 Search and typeahead** (`10-search-typeahead.md`). The indexing pipeline
  and its freshness, trie against search engine, sharding and ranking.

### Data

- **#11 ETL for batch and streaming, with lineage and replay**
  (`11-etl-batch-streaming.md`). Kappa against Lambda, CDC ingestion, replay
  from an immutable raw zone, lineage, late data and schema evolution.
- **#12 Data lake and warehouse** (`12-data-lake-warehouse.md`). Iceberg
  lakehouse against warehouse-native, raw, curated and serving zones,
  partitioning and clustering, access control and CMEK.
- **#13 Observability platform** (`13-observability-platform.md`). Metrics, logs
  and traces at scale, cardinality, sampling and retention tiers.

### Platform and resilience

- **#14 N-tier network architecture** (`14-n-tier-network.md`). Tier boundaries
  and controls, hub-spoke against flat, inspected egress and private service
  access. This one leans hardest on the repo's own modules.
- **#15 Data disaster recovery across data architectures**
  (`15-data-disaster-recovery.md`). RTO and RPO per tier, the ladder from
  backup-restore to active-active, replication modes and DR testing.
- **#16 Multi-region active-active global app** (`16-multi-region-active-active.md`).
  Global routing and DNS failover, data placement and residency, conflict
  resolution and cells.
- **#17 Multi-tenant SaaS isolation tiers** (`17-multi-tenant-saas.md`). Silo,
  pool and bridge models, noisy neighbours, per-tenant keys, and mapping
  tenants onto accounts and projects.
- **#18 Distributed job scheduler** (`18-distributed-job-scheduler.md`).
  Exactly-once triggering with leases, partitioned work, retries and dead
  letters, and cron at scale.

### AI

- **#19 LLM serving and RAG system** (`19-llm-serving-rag.md`). Batching, GPU
  capacity and model routing; ingestion, chunking and the vector store;
  guardrails, evaluation and cost per token.

## Conventions used across the library

- Facts that drift (service limits, quotas, provider arguments, latency and
  throughput figures, pricing models) carry an inline link to official docs and
  the marker "(checked 2026-11)".
- Anything the docs do not state is marked **verify before relying on**.
- Diagrams are Mermaid, with at most 15 nodes each.
- Snippets use google `~> 8.0` and aws `>= 6.46.0, < 7.0.0` argument names. A
  raw resource, used where the repo has no module, carries a one-line gap note.
- Names, tags and labels, CMEK, subnet tiers and identities follow the primer's
  [conventions](00-primer.md#conventions).
