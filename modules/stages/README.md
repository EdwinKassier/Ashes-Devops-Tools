# Stages Modules

Terraform modules implementing the **staged deployment pattern** for Google Cloud Landing Zones, aligned with [Foundation Fabric FAST](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric).

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         envs/organisation/                              │
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
                        ┌─────────┐ ┌─────────┐ ┌─────────┐
                        │envs/dev │ │envs/uat │ │envs/prod│
                        │         │ │         │ │         │
                        │ host    │ │ host    │ │ host    │
                        │ module  │ │ module  │ │ module  │
                        │         │ │         │ │         │
                        │workloads│ │workloads│ │workloads│◀── stages/workload
                        └─────────┘ └─────────┘ └─────────┘
```

## Modules

| Module | Stage | Purpose | Invoked From |
|--------|:-----:|---------|--------------|
| [bootstrap](./bootstrap/) | 0 | Admin project, Terraform SA, WIF | `envs/organisation/` |
| [organization](./organization/) | 1 | Folders, IAM, Org Policies, Tags | `envs/organisation/` |
| [projects](./projects/) | 2 | **Platform projects** (hosts, hubs) | `envs/organisation/` |
| [network-hub](./network-hub/) | 3 | Hub VPC, DNS, Hierarchical FW | `envs/organisation/` |
| [workload](./workload/) | N/A | **Application projects** (per-env) | `envs/{env}/workloads.tf` |

## Projects vs Workload: Key Distinction

> **These two modules serve different purposes and are NOT interchangeable.**

| Aspect | `projects` | `workload` |
|--------|-----------|-----------|
| **Creates** | Platform infrastructure | Application services |
| **When** | Once at org setup | On-demand per team |
| **Examples** | `dev-host`, `shared-hub` | `dev-api`, `prod-payment` |
| **Owner** | Platform Team | Application Teams |

See individual module READMEs for detailed usage.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	
}
```

## Requirements

No requirements.

## Providers

No providers.



## Resources

The following resources are created:




## Inputs

No inputs.

## Outputs

No outputs.

## Security Considerations

- Ensure all sensitive variables are marked as `sensitive = true`
- Use GCP Secret Manager for storing secrets
- Follow the principle of least privilege for IAM roles
- Enable audit logging for compliance

## Contributing

Contributions are welcome! Please read the [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

## License

This module is licensed under the MIT License. See [LICENSE](../../LICENSE) for details.
<!-- END_TF_DOCS -->