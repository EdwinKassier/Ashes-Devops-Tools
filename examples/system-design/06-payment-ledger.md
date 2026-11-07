# Payment system and ledger

This walkthrough follows the [interview framework](00-primer.md#interview-framework).
It uses the numbers in the [estimation cheat sheet](00-primer.md#estimation-cheat-sheet)
and the conventions in the [primer](00-primer.md#conventions). It reuses the
**transactional outbox** defined in the microservices walkthrough, under
[The transactional outbox](03-microservices-sync-async.md#the-transactional-outbox),
and does not re-explain it.

## The question

> "Design the payment system for an online marketplace. Customers pay by card
> through an external payment service provider (PSP). We need to charge them
> exactly once, record every movement of money in a ledger, and prove at the
> end of each day that our books match the provider's."

Common variants:

- "The client times out and retries a payment. How do you not charge twice?"
- "Design a double-entry ledger. What invariants does it enforce?"
- "The PSP's settlement file disagrees with your records. What happens?"
- "Where is exactly-once real in this system, and where is it a lie?"

## The two-minute answer

A **payments service** accepts `POST /payments` with a client-supplied
**idempotency key**, and records the key and the payment in one transaction
before anything else, so a retry finds the existing payment. It calls the PSP
with **its own** idempotency key, derived from the payment ID, so its own
retries cannot double-charge either. A PSP call that times out is explicitly
**unknown**, resolved by asking the PSP, never by charging again. Every
movement of money becomes an entry in an append-only **double-entry ledger**:
postings sum to zero per currency, and corrections are reversing entries,
never updates. The payment change and its ledger event commit together through
a transactional outbox, and PSP webhooks are deduplicated hints to re-read the
payment. Every day a **reconciliation** job matches the ledger against the
PSP's settlement report and the bank statement, and sends every mismatch to a
human queue. On AWS this is ECS on Fargate and Aurora PostgreSQL; on GCP,
Cloud Run and Cloud SQL for PostgreSQL.

```mermaid
graph LR
    client["Client / checkout"] --> pay["payments service"]
    pay -->|"idempotency key"| psp["PSP"]
    psp -->|webhooks| pay
    pay -->|outbox| ledger["ledger service<br/>(double-entry)"]
    psp -->|"settlement file"| recon["reconciliation job"]
    recon --> ledger
```

## Clarify the requirements

Questions to ask, with the answers assumed here:

| Question | Assumed answer |
|---|---|
| Who processes cards? | An external PSP. Card numbers never touch our systems: the checkout page uses the PSP's hosted fields and we only see tokens. |
| Which flows? | Authorise, capture, refund, and the PSP's settlement to our bank account. Payouts to sellers exist but are out of scope beyond their ledger entries. |
| Scale? | 5 million payments a day; peaks of 5× average during sales. |
| Latency? | `POST /payments` p99 under 3 seconds, dominated by the PSP. |
| Correctness? | No double charge, no lost capture, and a ledger that balances at every commit. Money is never a float. |
| Currencies? | Several, each in integer minor units. No FX inside a journal entry. |
| Audit? | Every movement traceable to a request, PSP event and settlement line, for years. |
| Regions? | One region, multi-AZ. Multi-region is the active-active walkthrough. |

Non-functional: 99.95% availability for accepting payments; RPO zero within
the region (synchronous cross-zone replication); RTO of minutes; CMEK on all
money data.

On card data: keeping card numbers out of our systems is what keeps the PCI
DSS scope small. Which self-assessment questionnaire applies depends on the
integration; **verify before relying on** any scope claim with your assessor.

## Back-of-envelope estimates

Arithmetic uses the primer's [QPS conversions](00-primer.md#qps-conversions).

**Payments.** 5 million a day is about 58 a second. At 5× peak that is about
300 a second; design for **500 payments a second**.

**PSP calls.** Authorise plus capture, and a few refunds: about **1,000 PSP
calls a second** at peak. Assume a PSP p99 of 2 s (**verify before relying
on** for your PSP). By Little's law that is **2,000 calls in flight**, which
sizes connection pools and task count, not CPU.

**Ledger postings.** A payment produces about four journal entries over its
life (capture, PSP fee, settlement, seller payable) with two or three postings
each: call it **10 postings per payment**. That is 50 million postings a day,
about 580 a second on average and **5,000 a second at design peak**. At about
250 bytes a row including indexes, that is about 12.5 GB a day, or about
4.6 TB a year. Two decisions follow:

- 5,000 inserts a second is inside the
  [folk rule](00-primer.md#throughput-per-instance-and-per-partition) for one
  relational primary, so **one PostgreSQL primary, no sharding**, at this scale.
- Multi-terabyte growth means **monthly partitions**, with old ones exported
  to the raw zone and detached.

**Hot accounts.** Every payment posts to the PSP clearing account. As one
balance row updated in place, it would serialise 5,000 postings a second on
one lock that sustains perhaps a few hundred updates a second (**verify before
relying on**; measure it). So hot balances are **derived**, never updated.

**Idempotency records.** 5 million keys a day at about 2 KB each (the request
hash and the stored response) is 10 GB a day. Kept 72 hours: about 30 GB.

**Webhooks.** About three events per payment: about 175 a second on average.
PSP retries after an outage arrive in a burst; plan for **10×**, about 1,750 a
second.

**Reconciliation.** About 5 million settlement lines at 300 bytes: **1.5 GB a
day**, matched by key in one hash join. Minutes in a batch, not a streaming
problem.

## API and data model

### Synchronous API

| Endpoint | Purpose | Notes |
|---|---|---|
| `POST /payments` | Create and authorise a payment. | Requires `Idempotency-Key`. Returns `201` with the payment, or the stored response on a retry. |
| `POST /payments/{id}/capture` | Capture an authorised payment. | Idempotency key required; the amount may be partial. |
| `POST /payments/{id}/refunds` | Refund all or part of a capture. | Idempotency key required. |
| `GET /payments/{id}` | Current status. | No key: reads are idempotent. |
| `POST /webhooks/psp` | PSP event delivery. | Signature-verified; returns `200` fast after a durable insert. |
| `GET /ledger/accounts/{id}/balance` | Balance as of now or a timestamp. | Internal only. |

Key handling follows the IETF
[Idempotency-Key header draft](https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/),
which is still an Internet-Draft (revision 08, October 2026; checked 2026-11).
Its revision 07 recommends `400` when a required key is missing, `409` while
the original request is still in progress, and `422` when a key is reused
with a different payload
([draft section 2.7](https://www.ietf.org/archive/id/draft-ietf-httpapi-idempotency-key-header-07.html),
checked 2026-11).

### Events

payments writes `PaymentAuthorized`, `PaymentCaptured`, `PaymentRefunded`,
`PaymentFailed` and `PspFeeCharged` to its outbox (envelope as in the
[microservices walkthrough](03-microservices-sync-async.md#events)); the ledger
turns each into one journal entry.

### Key tables

| Table | Owner | Key | Access pattern |
|---|---|---|---|
| `idempotency_keys` | payments | `(merchant_id, key)` | Insert-or-read at the start of every write request; expire after 72 hours. |
| `payments` | payments | `payment_id`; unique `(merchant_id, idempotency_key)` | Point read and state transition by ID. |
| `psp_attempts` | payments | `(payment_id, operation)`; unique `psp_idempotency_key` | One row per call to the PSP, with its outcome: `succeeded`, `failed` or `unknown`. |
| `psp_events` | payments | `psp_event_id` | Inbox: insert on webhook receipt; a key conflict is a duplicate. |
| `accounts` | ledger | `account_id` | Chart of accounts: type (asset, liability, revenue, expense), currency, `hot` flag. |
| `journal_entries` | ledger | `entry_id`; unique `source_event_id` | Append-only; one per business event. |
| `postings` | ledger | `(entry_id, line)`; index `(account_id, created_at)` | Append-only, partitioned by month; balances are sums. |
| `balance_snapshots` | ledger | `(account_id, as_of)` | Periodic checkpoints so a balance is snapshot + recent postings. |
| `settlement_lines` | recon | `(psp, psp_reference)` | Loaded from the raw zone; matched against postings. |
| `recon_breaks` | recon | `break_id` | Open mismatches with category, amount and owner. |

Amounts are `bigint` minor units plus an ISO 4217 currency code. A float never
holds money.

## High-level design

```mermaid
graph TB
    client["Client / checkout"] --> edge["Edge: CloudFront + WAF / external ALB + Cloud Armor"]
    pspwh["PSP webhooks"] --> edge
    edge --> pay["payments service"]
    pay --> pdb[("payments DB<br/>payments, keys, attempts,<br/>inbox, outbox")]
    pay -->|"HTTPS, inspected or NAT egress"| psp["PSP API"]
    pdb --> relay["outbox relay"]
    relay --> topic(["payment events"])
    topic --> ledger["ledger service"]
    ledger --> ldb[("ledger DB<br/>entries, postings")]
    pspfile["PSP settlement report"] --> raw[("raw zone bucket<br/>WORM")]
    raw --> recon["reconciliation job"]
    recon -->|"postings by date, via API"| ledger
    recon --> breaks["breaks queue<br/>(humans)"]
```

### Write path: a card payment

1. The client sends `POST /payments` with `Idempotency-Key: k1`, an amount and
   a PSP payment-method token.
2. payments inserts `(merchant, k1)` into `idempotency_keys` with the request
   hash and status `in_progress`, and the payment row in `CREATED`, **in one
   transaction**. A key conflict means a retry: return the stored response,
   `409` if still in progress, or `422` if the request hash differs.
3. payments commits a `psp_attempts` row with
   `psp_idempotency_key = payment_id + ":authorize"`, and only then calls the
   PSP. This is the **recovery point**.
4. In one transaction, payments records the outcome, moves the payment to
   `AUTHORIZED` (or `FAILED`), writes `PaymentAuthorized` to the outbox and
   stores the response on the idempotency key. It returns `201`.
5. On a timeout or `5xx` the attempt is `unknown`, the payment `PENDING_PSP`,
   and the client gets `202`. A resolver retries with the **same** PSP key, or
   looks the payment up by our reference, until the outcome is known.
6. The relay publishes the event; the ledger writes a balanced entry,
   deduplicated by `source_event_id`. Capture and refund work the same way.

### Read path: balance

The latest `balance_snapshots` row plus the postings since it. Snapshots are
written every few minutes, so a read sums minutes of postings, not years.

### Webhook path

payments verifies the signature, inserts the event into `psp_events` (a
conflict means a duplicate), returns `200`, and processes it later, as the
exactly-once deep dive describes.

## Deep dives

### Idempotency keys

There are **three** idempotency boundaries, and each needs its own key.

| Boundary | Key | Who enforces it | Window |
|---|---|---|---|
| Client → payments | `Idempotency-Key` header, scoped per merchant | Our `idempotency_keys` table | 72 hours (our choice) |
| payments → PSP | `payment_id:operation`, stored on `psp_attempts` | The PSP | The PSP's window |
| PSP → payments (webhooks) | `psp_event_id` | Our `psp_events` inbox | As long as the inbox is kept |

**Client to us.** The key row and the payment row commit together, so neither
exists without the other. Store a hash of the request body and reject a reused
key with a different body (`422`). Scope keys per merchant. Return the
**stored** response on a retry, including a stored decline.

**Us to the PSP.** Stripe, as one example, keeps the result of the first
request with a key and returns it to retries, **including `500` errors**. It
rejects a reused key with different parameters, accepts keys up to 255
characters, and may prune a key once it is at least 24 hours old, after which
the same key creates a new request
([Stripe docs](https://docs.stripe.com/api/idempotent_requests), checked 2026-11).
Two design rules follow:

- **Derive the PSP key deterministically** from the payment ID and the
  operation, and store it before the call. A restarted process recomputes the
  same key; a random key per attempt would charge twice.
- **Never rely on the PSP key past its window.** A resolver that wakes up days
  later first looks the payment up at the PSP by our reference, and re-sends
  only if the PSP has no record. Other PSPs have other windows (the adapter
  gateway walkthrough covers per-backend capabilities).

**Concurrency and crashes.** Two concurrent retries race on the unique
constraint: the loser gets `409` while the winner is `in_progress`. A request
that dies holding `in_progress` leaves a lease (`locked_until`); after it
expires, a retry resumes from the last committed phase. The phases are: record
key and payment; record the PSP attempt; call the PSP; record the outcome.
Each is idempotent given the one before, which makes a crash at any line safe.

**Where it breaks.** A client that generates a new key per retry defeats all
of this; make the SDK do it right.

### Double-entry ledger invariants

The ledger records **every movement of money as a journal entry with two or
more postings**. Each posting debits or credits one account. In this design a
posting is a signed amount: debits positive, credits negative.

The invariants, in the order an interviewer usually asks:

1. **Balanced entries.** For every journal entry, the postings sum to zero
   **per currency**. A cross-currency movement is two entries through an FX
   account, each balanced in its own currency.
2. **Append-only.** Postings and entries are never updated or deleted. A
   mistake is corrected by a **reversing entry** and a new correct entry, so
   history is never rewritten.
3. **Integer minor units.** `bigint` amounts and a currency code. Rounding
   happens once, at the edge, by an explicit rule.
4. **Traceability.** Every entry carries a unique `source_event_id`, which
   also makes the consumer idempotent.
5. **Derived balances.** A balance is the sum of postings; snapshots are a
   recomputable cache.
6. **Global zero.** So all postings in a currency sum to zero: a cheap nightly
   corruption check.

A capture of 100.00 GBP with a 1.50 fee, as two entries:

| Entry | Account | Amount (minor units) |
|---|---|---|
| capture | `psp_clearing` (asset) | +10000 |
| capture | `seller_payable` (liability) | −9000 |
| capture | `platform_revenue` (revenue) | −1000 |
| fee | `psp_fees` (expense) | +150 |
| fee | `psp_clearing` (asset) | −150 |

When the PSP settles, a third entry moves 9,850 from `psp_clearing` to
`bank_operating`. Once everything has settled, `psp_clearing` returns to zero,
and that is what reconciliation checks.

**Enforcing it in PostgreSQL.**

- **Balanced:** insert an entry and its postings in one transaction, and add a
  `DEFERRABLE INITIALLY DEFERRED` constraint trigger on `postings` that checks
  the entry's sum per currency at commit. An unbalanced entry cannot commit.
- **Append-only:** the application's database role gets `INSERT` and `SELECT`
  only; `UPDATE`, `DELETE` and `TRUNCATE` are revoked. A trigger that raises on
  update or delete is a second line.
- **Non-negative accounts** (a seller cannot be paid out more than they are
  owed): lock the account row with `SELECT … FOR UPDATE` in the entry's
  transaction and check the derived balance. PostgreSQL's default isolation is
  Read Committed; at Repeatable Read or Serializable the application must retry
  whole transactions that fail with SQLSTATE `40001`
  ([PostgreSQL docs](https://www.postgresql.org/docs/current/transaction-iso.html),
  checked 2026-11). Explicit row locks on the few constrained accounts are
  simpler than running everything at Serializable.

**The hot-account fix.** `psp_clearing` and `platform_revenue` take a posting
from almost every payment. Three options:

| Option | Wins | Breaks |
|---|---|---|
| Balance column updated per posting | Simple reads. | One row lock serialises every payment: the hot-row ceiling from the estimates. |
| **Derived balance plus snapshots** (chosen for hot accounts) | Inserts never contend; postings are append-only rows. | Reads cost a snapshot plus a range sum. Hot accounts cannot have an overdraft check, which is fine: they are the platform's own. |
| Split a hot account into N sub-accounts | Spreads lock contention. | Reporting must sum the sub-accounts. Use it only if a hot account really needs a locked balance check. |

**Alternatives.** DynamoDB transactions group up to 100 actions and 4 MB
atomically, with a client token valid for 10 minutes
([AWS docs](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis.html),
checked 2026-11): enough for an entry, but balances and audits become
application code. Spanner behaves as if all transactions ran one after another,
across regions
([Google Cloud docs](https://docs.cloud.google.com/spanner/docs/true-time-external-consistency),
checked 2026-11): choose it for a multi-region active-active ledger.

**Where it breaks.** Past one primary's insert ceiling, shard by account
group, and entries that span shards need a two-phase pattern of their own.

### Reconciliation with external providers

The ledger records what **we believe** happened. Reconciliation proves it
against the **PSP** and the **bank**, and catches every bug the rest missed.

**Three-way match.**

1. **Ledger to PSP transactions.** Each capture, refund and fee posting
   against the PSP's settlement report, matched on the PSP reference (stored on
   `psp_attempts`) and amount.
2. **PSP payout to bank.** Each payout batch in the settlement report against
   the credit on the bank statement.
3. **Clearing to zero.** `psp_clearing` should hold only payments captured but
   not yet settled. Its balance must equal the sum of open captures.

**Flow.** The PSP's report lands in the **raw zone** exactly as received,
with retention locked ([Data zones](00-primer.md#data-zones)), so any run can be
repeated and audited. The job loads it into `settlement_lines`, matches, and
opens a break for everything unmatched.

**Break categories.** Each has an owner and an action:

| Break | Usual cause | Action |
|---|---|---|
| In PSP, not in ledger | A webhook or event was lost, or a capture outcome stayed `unknown` | Resolve the attempt from the PSP; the ledger then posts it. Never post straight from the file without the payment record. |
| In ledger, not in PSP | Timing (settles tomorrow), or we recorded a capture that failed | Age it: within the settlement window it is timing; after it, investigate. |
| Amount mismatch | Fees, FX, partial capture, rounding | Post an adjustment entry to a named account, with the break ID. |
| Duplicate at PSP | A double charge: two PSP charges for one payment | Refund one, post the refund, and treat it as an incident. |

**Timing.** Settlement lags capture by days, so matching runs on a rolling
window and a break counts only once older than the settlement delay. Unmatched
money sits in a **suspense account**, never silently adjusted.

**Where it breaks.** A silently changed report format (schema-check on
arrival), a partial file (check the trailer's count and totals), and volume
(at ×100 the match becomes a warehouse job).

### Exactly-once boundaries

Exactly-once is real in exactly one place: **inside one database
transaction**. Everywhere else the system is at-least-once with idempotency,
and the design has to say which.

| Hop | Delivery | What makes it effectively-once |
|---|---|---|
| Client → payments | At-least-once (clients retry) | Client idempotency key, stored with the payment in one transaction |
| payments → PSP | At-least-once, and the outcome can be **unknown** | Deterministic PSP key; resolve unknowns by lookup |
| PSP → payments (webhooks) | At-least-once, unordered | `psp_events` inbox keyed by event ID; webhooks only trigger a re-read |
| payments → ledger | At-least-once (the outbox publishes at least once) | Outbox for atomic publish ([see the outbox](03-microservices-sync-async.md#the-transactional-outbox)); unique `source_event_id` on entries |
| PSP report → reconciliation | Re-runnable | Immutable raw file; matching is a pure function of inputs |

```mermaid
sequenceDiagram
    participant C as Client
    participant P as payments
    participant DB as payments DB
    participant S as PSP
    C->>P: POST /payments (Idempotency-Key k1)
    P->>DB: insert key k1, payment, attempt (commit)
    P->>S: authorize (key pay_1:authorize)
    S--xP: timeout
    P->>DB: attempt = unknown, payment = PENDING_PSP
    P-->>C: 202 PENDING_PSP
    P->>S: retry authorize (same key) or look up by reference
    S-->>P: authorized
    P->>DB: AUTHORIZED + outbox event (one commit)
```

**The unknown outcome is the core idea.** A timeout means you do not know.
Treating it as failure invites the classic double charge; treating it as
success loses money. Only `unknown`, resolved by the same key or a lookup, is
safe.

**Webhooks are hints, not commands.** Stripe retries undelivered events for up
to three days in live mode, does not guarantee order, may send duplicates, and
asks for a `2xx` before complex work. It signs with HMAC-SHA256 over a
timestamp and the body, and its libraries reject timestamps older than 5
minutes by default
([Stripe docs](https://docs.stripe.com/webhooks), checked 2026-11). So verify,
store and acknowledge; then re-read the payment from the PSP and apply only
forward transitions, so a late or duplicated event cannot regress state.

## Trade-offs to defend

| Decision | Chosen | Rejected | Why | What would change the answer |
|---|---|---|---|---|
| Ledger store | PostgreSQL (Aurora / Cloud SQL), one primary | DynamoDB; Spanner | Constraints, triggers and SQL audits; 5,000 postings/s fits one primary. | Multi-region active writes (Spanner), or ×100 volume. |
| Balances | Derived from postings plus snapshots | Balance column per account | No hot-row contention; balances are recomputable. | An account that needs an overdraft check at high write rate: split it. |
| Corrections | Reversing entries | Updating postings | History is evidence. | Nothing: not negotiable. |
| PSP timeout | `unknown` state plus resolver | Treat as failure | Cannot double-charge or lose money. | Nothing realistic; even a reliable status API needs the state. |
| Payments → ledger | Outbox, async consumer | Sync ledger call | The event commits with the payment; no extra hop. | The response must show the new ledger balance. |
| Webhooks | Inbox, ack fast, re-read the PSP | Apply the payload | Unordered duplicates cannot regress state. | A PSP sending ordered, versioned snapshots. |
| Reconciliation | Daily three-way batch, suspense account | Real-time matching | Settlement arrives daily; batch is easy to re-run. | Streaming settlement and intra-day treasury needs. |

## Failure modes and scaling limits

**At ×10 (5,000 payments a second, 50,000 postings a second):**

- **The ledger primary fails first:** 50,000 inserts a second is past one
  primary's comfort zone. Batch inserts, then shard by account group.
- **PSP concurrency:** 20,000 calls in flight. Pools, file descriptors and the
  PSP's rate limits bind before compute.
- **Idempotency table:** 300 GB at 72 hours; partition by day.

**At ×100:** a sharded or distributed ledger (Spanner, or PostgreSQL shards by
account group), a second PSP behind the adapter gateway, and reconciliation as
a warehouse job.

**Blast radius by component:**

| Component | If it fails | Blast radius |
|---|---|---|
| PSP API | Attempts go `unknown`; payments `PENDING_PSP` | New payments stall; no money is lost. The runbook below. |
| payments DB | No new payments | The whole write path. Multi-AZ first. |
| Outbox relay or broker | Ledger falls behind | Ledger lag only; payments continue. |
| ledger DB | Ledger consumer backs up | Balances and payouts stall; payments continue. |
| Webhook receiver | PSP retries for days | Status lags; the resolver still polls. |
| Reconciliation job | Not matched today | Detection delayed; re-run from the raw file. |
| KMS key disabled | Encrypted stores stop serving | Everything that key encrypts: a Cloud SQL instance suspends while its key is disabled ([Google Cloud docs](https://docs.cloud.google.com/sql/docs/postgres/cmek), checked 2026-11). |

**Database failover.** Aurora replicates synchronously to six storage nodes
across Availability Zones, and a failover to a replica typically completes in
under 60 seconds, often under 30
([AWS docs](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Concepts.AuroraHighAvailability.html),
checked 2026-11). Cloud SQL high availability writes synchronously to disks in
two zones and fails over in about sixty seconds
([Google Cloud docs](https://docs.cloud.google.com/sql/docs/postgres/high-availability),
checked 2026-11). In-flight requests fail and are retried with the same keys.

## AWS and GCP mapping

| Component | AWS | GCP | Difference that matters |
|---|---|---|---|
| Services | ECS on Fargate | Cloud Run | The relay and resolver are background loops; on Cloud Run they need instance-based billing or a request trigger. |
| Ledger and payments DBs | Aurora PostgreSQL | Cloud SQL for PostgreSQL | Aurora backup retention is 1–35 days, default 1 ([AWS docs](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Managing.Backups.html), checked 2026-11). Cloud SQL point-in-time log retention is 1–7 days on Enterprise and 1–35 on Enterprise Plus ([Google Cloud docs](https://docs.cloud.google.com/sql/docs/postgres/backup-recovery/configure-pitr), checked 2026-11). |
| CMEK on the DB | Workload CMK, set by app-services | Cloud SQL CMEK, **creation time only** | Cloud SQL cannot add or change CMEK on an existing instance, and the key ring must be in the instance's region ([Google Cloud docs](https://docs.cloud.google.com/sql/docs/postgres/cmek), checked 2026-11). |
| Raw zone (settlement files) | S3 with Object Lock | Cloud Storage with a locked retention policy | S3 compliance mode stops even the root user deleting a locked version, and needs versioning ([AWS docs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html), checked 2026-11). A locked GCS policy can never be removed or shortened, up to 100 years ([Google Cloud docs](https://docs.cloud.google.com/storage/docs/bucket-lock), checked 2026-11). |
| Public webhook ingress | CloudFront VPC origin to the internal ALB, with WAF | External Application Load Balancer per exposed service, with Cloud Armor | AWS exposes the **shared** ALB; GCP exposes **one service**. See Build it here. |
| Egress to the PSP | TGW → Network Firewall → central NAT, domain allowlist | Per-environment Cloud NAT, not inspected | AWS can allowlist the PSP's hostname; GCP needs an addition such as Cloud NGFW or Secure Web Proxy for that. |
| Reconciliation runtime | ECS service with a daily loop | Cloud Run job | GCP has a job runtime in app-services; AWS app-services has none. |

## Build it here

### Where it lives

| Part | AWS | GCP |
|---|---|---|
| payments, ledger, recon | `aws-workload-prod` (`envs/aws/workload`) through [`modules/aws/stages/app-services`](../../modules/aws/stages/app-services/) | `gcp-workload-prod` (`envs/gcp/workload`) through [`modules/gcp/stages/app-services`](../../modules/gcp/stages/app-services/) in the environment stage |
| Databases | Aurora per service via [`modules/aws/data/rds-aurora`](../../modules/aws/data/rds-aurora/), isolated tier, workload CMK | Cloud SQL per service via [`modules/gcp/data/cloud-sql`](../../modules/gcp/data/cloud-sql/), Private Service Access, `workload_cmek` |
| Settlement raw zone | Raw S3 bucket in `envs/aws/workload` | Raw Cloud Storage bucket in `envs/gcp/workload` |
| Egress allowlist | `aws-network` (`envs/aws/network`) | None: Cloud NAT |
| Apply order | `aws-organization` → `aws-security` → `aws-network` → … → `aws-workload-prod` | `gcp-bootstrap` → `gcp-organization` → `gcp-projects` → `gcp-network-hub` → `gcp-workload-prod` (twice; see below) |

Placement follows [VPC-tier placement](00-primer.md#vpc-tier-placement):
services in `private`, Aurora in `isolated`, Cloud SQL on Private Service
Access. To keep the PCI-relevant blast radius and IAM apart from other
workloads, give payments a dedicated environment (an account added per
[Adding an AWS account](../../docs/runbooks/aws-add-account.md), and a GCP
project); the snippets use `prod` for brevity. The
reconciliation job reads ledger postings through the ledger service's API, not
its database: each service stays the only reader and writer of its own store.

### Config

```yaml
# Illustrative. Keys are real (config/landing-zone.schema.json); values are placeholders.
aws:
  workload:
    app_ingress_mode: cloudfront_vpc_origin # public HTTPS for PSP webhooks; see the gap below
  network:
    egress_domain_allowlist:
      - .amazonaws.com
      - api.stripe.com # the PSP API; nothing else on the internet
  workload_environments:
    prod:
      account_key: workload_prod
      vpc_cidr: 10.30.0.0/16
      is_production: true
      services:
        payments:
          path_patterns: ["/payments", "/payments/*", "/webhooks/psp"]
          autoscaling_max_capacity: 30
          enable_autoscaling: true
          secrets:
            PSP_API_KEY: arn:aws:secretsmanager:REGION:ACCOUNT_ID:secret:prod/psp-api-key
            PSP_WEBHOOK_SECRET: arn:aws:secretsmanager:REGION:ACCOUNT_ID:secret:prod/psp-webhook
          database:
            backup_retention_period: 35
        ledger:
          path_patterns: ["/ledger/*"]
          database:
            enable_serverless_v2: false # steady 5,000 inserts/s; provisioned
            instance_class: db.r6g.xlarge
            backup_retention_period: 35
        recon:
          path_patterns: ["/recon/*"]
          database: {}
gcp:
  workload:
    public_ingress:
      prod:
        payments:
          domains: [pay.my-org.example.com]
  environments:
    prod:
      cidr_block: 10.40.0.0/16
      region: europe-west2
      services:
        payments:
          vpc_egress: ALL_TRAFFIC # PSP calls leave through Cloud NAT
          min_instances: 2
          secrets:
            PSP_API_KEY: { secret: psp-api-key }
          database:
            enable_high_availability: true
            encryption_key_name: projects/HOST_PROJECT_ID/locations/europe-west2/keyRings/my-org-prod-cmek/cryptoKeys/payments-db
        ledger:
          min_instances: 2
          invoker_members:
            - serviceAccount:payments-run@HOST_PROJECT_ID.iam.gserviceaccount.com
            - serviceAccount:recon-run@HOST_PROJECT_ID.iam.gserviceaccount.com
          database:
            enable_high_availability: true
            encryption_key_name: projects/HOST_PROJECT_ID/locations/europe-west2/keyRings/my-org-prod-cmek/cryptoKeys/ledger-db
        recon:
          runtime: cloud-run-job
          timeout: 3600s
          database:
            encryption_key_name: projects/HOST_PROJECT_ID/locations/europe-west2/keyRings/my-org-prod-cmek/cryptoKeys/recon-db
```

Gaps in the golden path that this design hits:

- **AWS public ingress is all-or-nothing.** `app_ingress_mode` exposes the
  shared ALB, so `/ledger/*` and `/recon/*` become reachable through
  CloudFront too. Until app-services can expose one service, add a WAF rule
  allowing only `/payments*` and `/webhooks/psp`. GCP's `public_ingress`
  exposes the payments service alone.
- **Database roles.** AWS app-services hands the service the Aurora master
  secret; on GCP the runtime service account is the IAM database user. The
  append-only role (`INSERT`, `SELECT` only) must come from a schema migration.
- **GCP CMEK ordering.** Cloud SQL takes CMEK only at creation, and YAML
  cannot reference `module.workload_cmek`: apply the key ring below first, then
  add the `database` blocks. The Cloud SQL service identity must exist too:
  `gcloud beta services identity create --service=sqladmin.googleapis.com`
  ([Google Cloud docs](https://docs.cloud.google.com/sql/docs/postgres/configure-cmek),
  checked 2026-11).
- **Scheduling.** The GCP `recon` job needs a raw Cloud Scheduler trigger; on
  AWS, `recon` runs its own daily loop because app-services has no scheduled
  task.
- **PITR window on GCP.** `edition` defaults to `ENTERPRISE`, whose log
  retention stops at 7 days; `ENTERPRISE_PLUS` (default 14, up to 35) also
  needs an Enterprise Plus `tier` (**verify before relying on** the tier name).

### AWS: the settlement raw zone

In `envs/aws/workload`, using `local.environment`, `local.landing_zone_name`,
`local.kms_key_arn` and `module.app_services`. S3 encrypts through the
caller's IAM permissions, so the workload key policy needs no new statement
([CMEK source](00-primer.md#cmek-source)). Arguments checked against aws
v6.72.0
([`aws_s3_bucket`](https://registry.terraform.io/providers/hashicorp/aws/6.72.0/docs/resources/s3_bucket),
[`aws_s3_bucket_object_lock_configuration`](https://registry.terraform.io/providers/hashicorp/aws/6.72.0/docs/resources/s3_bucket_object_lock_configuration),
[`aws_s3_bucket_server_side_encryption_configuration`](https://registry.terraform.io/providers/hashicorp/aws/6.72.0/docs/resources/s3_bucket_server_side_encryption_configuration),
checked 2026-11).

```hcl
# Gap: the repo has no S3 raw-zone module; raw resources in the landing zone's conventions.
resource "aws_s3_bucket" "settlements_raw" {
  bucket              = "${local.landing_zone_name}-${local.environment}-settlements-raw" # org.name must be lowercase
  object_lock_enabled = true # versioning is enabled with it; set at creation only
  tags                = { Service = "recon" }
}

resource "aws_s3_bucket_object_lock_configuration" "settlements_raw" {
  bucket = aws_s3_bucket.settlements_raw.id
  rule {
    default_retention {
      mode  = "COMPLIANCE" # no principal, root included, can delete early
      years = 7            # set by your regulator, not by this example
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "settlements_raw" {
  bucket = aws_s3_bucket.settlements_raw.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "settlements_raw" {
  bucket                  = aws_s3_bucket.settlements_raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role_policy" "recon_settlements" {
  name = "recon-settlements-raw"
  role = split("/", module.app_services.services["recon"].task_role_arn)[1] # <env>-recon-task
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"], Resource = "${aws_s3_bucket.settlements_raw.arn}/*" },
      { Effect = "Allow", Action = "s3:ListBucket", Resource = aws_s3_bucket.settlements_raw.arn },
      { Effect = "Allow", Action = ["kms:GenerateDataKey", "kms:Decrypt"], Resource = local.kms_key_arn },
    ]
  })
}
```

Test in `GOVERNANCE` mode first: compliance-mode objects cannot be deleted
early by anyone.

### GCP: workload CMEK and the settlement raw zone

In `envs/gcp/workload`, using `local.env_config`, `local.project_prefix`,
`local.labels`, `var.environment` and `module.environment`. The key ring and
bucket are regional, so both use `local.env_config.region`. Arguments checked
against google v8.10.0
([`google_storage_bucket`](https://registry.terraform.io/providers/hashicorp/google/8.10.0/docs/resources/storage_bucket),
[`google_storage_bucket_iam_member`](https://registry.terraform.io/providers/hashicorp/google/8.10.0/docs/resources/storage_bucket_iam),
checked 2026-11).

```hcl
# Gap: no per-environment workload CMEK exists yet (see CMEK source);
# this adds one with the existing kms module. Apply it before any database.
module "workload_cmek" {
  source = "../../../modules/gcp/governance/kms"

  project_id   = local.env_config.host_project_id
  keyring_name = "${local.project_prefix}-${var.environment}-cmek"
  location     = local.env_config.region # Cloud SQL and the bucket need a same-region key
  labels       = local.labels
  keys = merge(
    { for k in ["payments-db", "ledger-db", "recon-db"] : k => {
      encrypter_decrypters = ["serviceAccount:service-${local.env_config.host_project_number}@gcp-sa-cloud-sql.iam.gserviceaccount.com"]
    } },
    { "settlements" = {
      encrypter_decrypters = ["serviceAccount:service-${local.env_config.host_project_number}@gs-project-accounts.iam.gserviceaccount.com"]
    } },
  )
}

# Gap: the repo has no locked raw-zone bucket module; raw resource in the landing zone's conventions.
resource "google_storage_bucket" "settlements_raw" {
  project                     = local.env_config.host_project_id
  name                        = "${local.project_prefix}-${var.environment}-settlements-raw"
  location                    = local.env_config.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = merge(local.labels, { service = "recon" })

  encryption {
    default_kms_key_name = module.workload_cmek.key_ids["settlements"]
  }

  retention_policy {
    retention_period = 220898160 # 7 years in seconds; set by your regulator
    is_locked        = false     # lock only after testing: it is irreversible
  }
}

resource "google_storage_bucket_iam_member" "recon_writer" {
  bucket = google_storage_bucket.settlements_raw.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${module.environment.app_services["recon"].runtime_service_account}"
}
```

The Cloud SQL service agent holds Encrypter/Decrypter on the three database
keys, and the Cloud Storage service agent on `settlements`; the key ring must
match the bucket's location
([Google Cloud docs](https://docs.cloud.google.com/storage/docs/encryption/using-customer-managed-keys),
checked 2026-11). `recon-run` also needs `roles/storage.objectViewer` on the
bucket to read files back. Per [Per-component identity](00-primer.md#per-component-identity),
these grants sit on the bucket, not the project.

## Runbook

### Payments stuck in PENDING_PSP: the PSP is timing out

**Detection signal.** The rate of `psp_attempts` that end `unknown`, emitted
by payments as a metric: alert above 1% for 5 minutes, page above 5%.
Corroborating: the count of payments in `PENDING_PSP` older than 5 minutes,
PSP call p99 latency, and the PSP's status page.

**Triage.**

1. **PSP or us?** Compare our PSP latency with the PSP's status page. Check
   egress: on AWS, Network Firewall alert logs in `aws-network` for drops to
   the PSP hostname after an `aws.network.egress_domain_allowlist` change; on
   GCP, Cloud NAT errors or port exhaustion.
2. **One operation or all?** One failing points at the PSP; all failing points
   at us (rotated secret, TLS, DNS).
3. **Is the resolver keeping up** once the PSP recovers?

**Mitigation.**

1. **Never** mark unknown attempts failed in bulk or ask clients to pay
   again: that turns an outage into double charges.
2. Shed load: `503` with `Retry-After` on `POST /payments` once in-flight PSP
   calls pass the pool limit.
3. With a second PSP behind the adapter gateway, route **new** payments to it.
   Unknown attempts stay with their original PSP.
4. Egress regression: revert through the owning workspace (`aws-network`) in
   Terraform Cloud, not by hand.
5. After recovery, the resolver drains unknowns oldest first within the PSP's
   rate limits: same key inside its window, lookup outside it.

**Verification.** The `unknown` rate is back near zero, no payment has been in
`PENDING_PSP` for more than 5 minutes, and the next reconciliation shows no
"in PSP, not in ledger" or duplicate-charge breaks for the incident window.

**Follow-up.** Reconcile the incident window early. Review the outbound
timeout against PSP p99. Game-day a PSP blackhole in staging.

### The ledger does not balance, or reconciliation breaks spike

**Detection signal.** The nightly global-zero check (sum of postings per
currency is not zero), or reconciliation breaks above their normal daily count.

**Triage.** Global zero failing means an unbalanced entry got in: was the
deferred constraint trigger dropped by a migration? A break spike usually means
lost events (outbox lag, a DLQ) or a changed report format.

**Mitigation.** Freeze payouts. Fix forward with reversing and correcting
entries that cite the break ID; never edit postings. Re-run reconciliation from
the raw file.

**Verification.** Global zero holds, `psp_clearing` equals the sum of open
captures, and the break count is back to baseline.

**Follow-up.** Add the case to the ledger's invariant tests. If a migration
removed a trigger, add a schema check for it to CI.

## Study aids

### Numbers to memorise

| Fact | Value |
|---|---|
| This design's peak | 500 payments/s, 1,000 PSP calls/s, 5,000 postings/s |
| Ledger growth | ~12.5 GB/day, ~4.6 TB/year |
| Stripe idempotency | Keys up to 255 characters; prunable after 24 hours; replays stored `500`s |
| Stripe webhooks | Retries for up to 3 days live; unordered; signature tolerance 5 minutes |
| IETF Idempotency-Key draft | `400` missing, `409` in progress, `422` payload mismatch |
| Aurora | 6 storage nodes across AZs; failover usually under 60 s; backups 1–35 days |
| Cloud SQL | HA failover about 60 s; PITR logs 7 days (Enterprise), 35 (Enterprise Plus); CMEK at creation only |
| DynamoDB transactions | 100 actions, 4 MB, client token 10 minutes |

### Likely follow-ups

- **"How do you guarantee exactly-once charging?"** You get effectively-once:
  a deterministic PSP key recorded before the call, and an `unknown` state
  resolved by the same key or a lookup.
- **"Why double-entry?"** Money cannot appear or vanish, zero-sum entries give
  a cheap global check, and the postings are the audit trail.
- **"Why not keep a balance column?"** Hot accounts serialise every payment on
  one row lock. Derive balances; snapshot for speed.
- **"The webhook says refunded but you have no capture."** Webhooks are
  unordered hints. Store it, re-read the payment from the PSP, and apply only
  forward transitions.

### Classic mistakes

- Floats for money.
- A random PSP idempotency key per retry.
- Treating a timeout as a failure and letting the client pay again.
- Updating or deleting ledger rows.
- Applying webhook payloads directly, in arrival order.
- Reconciliation that adjusts silently instead of opening breaks.
- Putting card numbers in your own database.

### Further reading

- [Stripe idempotent requests](https://docs.stripe.com/api/idempotent_requests)
- [Stripe webhooks: delivery behaviours](https://docs.stripe.com/webhooks)
- [IETF Idempotency-Key header draft](https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/)
- [PostgreSQL transaction isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
- The [transactional outbox](03-microservices-sync-async.md#the-transactional-outbox)
  and the primer's [service map](00-primer.md#aws-gcp-service-map).
