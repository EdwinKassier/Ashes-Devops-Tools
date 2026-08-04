# Modules

Terraform modules, **grouped by owning cloud (domain)**. Each cloud is a
self-contained bounded context:

```text
modules/
  gcp/        GCP-native primitives + stages/ (bootstrap, organization, projects, network-hub, workload)
  aws/        AWS primitives + stages/ (organization, security, network-hub, shared-services, backup, workload)
  supabase/   project, settings, environment, vault-secrets
  vercel/     project
  saas/       stages/saas-workload — composes supabase + vercel
```

Primitives are single-purpose building blocks (a VPC, a KMS key, an IAM role).
**Stages** are orchestration wrappers that compose primitives into a deployable
layer, invoked from a root under `envs/`.

## GCP staged deployment pattern

The GCP landing zone follows a staged pattern aligned with
[Foundation Fabric FAST](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric):

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                          envs/gcp-organization/                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  │
│  │  bootstrap   │─▶│ organization │─▶│   projects   │─▶│ network-hub │  │
│  │  (Stage 0)   │  │  (Stage 1)   │  │  (Stage 2)   │  │  (Stage 3)  │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └─────────────┘  │
│         │                 │                 │                 │         │
│     Admin SA          Folders          Host Projects       Hub VPC      │
│     WIF Pools        Org Policies      DNS Projects       VPC-SC        │
└─────────────────────────────────────────────────────────────────────────┘
                                          │
                              ┌───────────┼───────────┐
                              ▼           ▼           ▼
                        ┌─────────────────────────────┐
                        │      envs/gcp-workload      │
                        │ TF_WORKSPACE=gcp-workload-* │
                        │                             │
                        │ host module per env         │
                        │ workload attachments        │◀── gcp/stages/workload
                        └─────────────────────────────┘
```

| Module | Stage | Purpose | Invoked From |
|--------|:-----:|---------|--------------|
| [gcp/stages/bootstrap](./gcp/stages/bootstrap/) | 0 | Admin project, Terraform SA, WIF | `envs/gcp-organization/` |
| [gcp/stages/organization](./gcp/stages/organization/) | 1 | Folders, IAM, Org Policies, Tags | `envs/gcp-organization/` |
| [gcp/stages/projects](./gcp/stages/projects/) | 2 | **Platform projects** (hosts, hubs) | `envs/gcp-organization/` |
| [gcp/stages/network-hub](./gcp/stages/network-hub/) | 3 | Hub VPC, DNS, Hierarchical FW | `envs/gcp-organization/` |
| [gcp/stages/workload](./gcp/stages/workload/) | N/A | **Application projects** (per-env) | `examples/workloads/` |
| [saas/stages/saas-workload](./saas/stages/saas-workload/) | N/A | Supabase + Vercel full-stack environment | per-env workload root |

The AWS landing zone follows the same primitive/stage split under `aws/` — see
[AWS Landing Zone](../docs/architecture/aws-landing-zone.md).

## Projects vs Workload: key distinction

> **These two GCP stage modules serve different purposes and are NOT interchangeable.**

| Aspect | `gcp/stages/projects` | `gcp/stages/workload` |
|--------|-----------------------|-----------------------|
| **Creates** | Platform infrastructure | Application services |
| **When** | Once at org setup | On-demand per team |
| **Examples** | `apps-host`, `shared-hub` | `api-service`, `payments-service` |
| **Owner** | Platform Team | Application Teams |

See individual module READMEs for detailed usage.
