# Stages Modules

Terraform modules implementing the **staged deployment pattern** for Google Cloud Landing Zones, aligned with [Foundation Fabric FAST](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric).

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         envs/organization/                              │
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
                        ┌───────────────────────┐
                        │       envs/apps       │
                        │  TF_WORKSPACE=apps-*  │
                        │                       │
                        │ host module per env   │
                        │ workload attachments  │◀── stages/workload
                        └───────────────────────┘
```

## Modules

| Module | Stage | Purpose | Invoked From |
|--------|:-----:|---------|--------------|
| [bootstrap](./bootstrap/) | 0 | Admin project, Terraform SA, WIF | `envs/organization/` |
| [organization](./organization/) | 1 | Folders, IAM, Org Policies, Tags | `envs/organization/` |
| [projects](./projects/) | 2 | **Platform projects** (hosts, hubs) | `envs/organization/` |
| [network-hub](./network-hub/) | 3 | Hub VPC, DNS, Hierarchical FW | `envs/organization/` |
| [workload](./workload/) | N/A | **Application projects** (per-env) | `examples/workloads/` |
| [saas-workload](./saas-workload/) | N/A | Supabase + Vercel full-stack environment | per-env workload root |

## Projects vs Workload: Key Distinction

> **These two modules serve different purposes and are NOT interchangeable.**

| Aspect | `projects` | `workload` |
|--------|-----------|-----------|
| **Creates** | Platform infrastructure | Application services |
| **When** | Once at org setup | On-demand per team |
| **Examples** | `apps-host`, `shared-hub` | `api-service`, `payments-service` |
| **Owner** | Platform Team | Application Teams |

See individual module READMEs for detailed usage.
