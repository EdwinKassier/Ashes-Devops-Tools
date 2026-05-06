# Network Topology

This document describes the GCP network architecture deployed by this landing zone: a hub-spoke VPC topology with VPC Service Controls and Workload Identity Federation trust.

---

## Hub-Spoke Overview

```mermaid
graph TB
    subgraph org["GCP Organization"]
        direction TB

        subgraph hub_proj["Hub Project (network-hub)"]
            hub_vpc["Hub VPC\n10.0.0.0/16"]
            shared_vpc["Shared VPC Host"]
            cloud_nat["Cloud NAT\n(egress)"]
            dns_zone["Private DNS Zone\n*.internal.example.com"]
            vpn["HA-VPN\n(optional)"]
            interconnect["Interconnect\n(optional)"]
        end

        subgraph spoke_dev["Spoke Project — dev"]
            dev_vpc["Shared VPC\n(service project)"]
            dev_private["Private Subnet\n10.128.0.0/20"]
            dev_db["Database Subnet\n10.128.16.0/20"]
        end

        subgraph spoke_staging["Spoke Project — staging"]
            staging_vpc["Shared VPC\n(service project)"]
            staging_private["Private Subnet\n10.129.0.0/20"]
        end

        subgraph admin_proj["Admin Project (bootstrap)"]
            tf_sa["Terraform SA"]
            wif_github["WIF Pool\ngithub-pool"]
            wif_tfc["WIF Pool\ntfc-pool"]
        end

        hub_vpc -->|"VPC Peering"| spoke_dev
        hub_vpc -->|"VPC Peering"| spoke_staging
        hub_vpc --> cloud_nat
        hub_vpc --> dns_zone
        hub_vpc -.->|"optional"| vpn
        hub_vpc -.->|"optional"| interconnect
    end

    subgraph onprem["On-Premises / Remote Network"]
        corp_net["Corporate Network"]
    end

    subgraph ci["CI/CD — GitHub Actions"]
        gh_actions["GitHub Actions\nRunner"]
    end

    subgraph tfc["Terraform Cloud"]
        tfc_run["TFC Run Agent"]
    end

    vpn -->|"IPsec tunnels\n(HA-VPN)"| corp_net
    interconnect -->|"Dedicated\n10 Gbps VLAN"| corp_net

    gh_actions -->|"OIDC token\n(no static key)"| wif_github
    tfc_run -->|"OIDC token\n(no static key)"| wif_tfc
    wif_github -->|"impersonates"| tf_sa
    wif_tfc -->|"impersonates"| tf_sa
    tf_sa -->|"manages"| hub_proj
    tf_sa -->|"manages"| spoke_dev
    tf_sa -->|"manages"| spoke_staging
```

---

## VPC Service Controls Boundary

When `vpc_service_controls.enabled = true`, a VPC-SC perimeter wraps the spoke project. Services listed in `restricted_services` (e.g., BigQuery, Cloud Storage, Secret Manager) cannot be called from outside the perimeter without an explicit ingress policy.

```mermaid
graph LR
    subgraph perimeter["VPC-SC Perimeter — prod_perimeter"]
        spoke["Spoke Project\n(protected)"]
        bq["BigQuery"]
        gcs["Cloud Storage"]
        sm["Secret Manager"]
    end

    cicd["CI/CD\n(WIF ingress policy)"]
    external["External caller\n(blocked)"]

    cicd -->|"ingress policy\nallows"| bq
    cicd -->|"ingress policy\nallows"| gcs
    external -->|"access denied\nby perimeter"| bq
    external -->|"access denied\nby perimeter"| gcs
```

The perimeter starts in **dry-run mode** (`enable_dry_run = true`) — violations are logged to Cloud Audit Logs but not blocked. Flip to enforcement after validating that all legitimate callers have ingress policies.

---

## Workload Identity Federation Trust

No long-lived service account keys are used anywhere in the CI/CD pipeline.

```mermaid
sequenceDiagram
    participant GHA as GitHub Actions
    participant OIDC as GitHub OIDC IdP
    participant WIF as GCP WIF Pool<br/>(github-pool)
    participant STS as GCP STS
    participant SA as Terraform SA

    GHA->>OIDC: Request ID token<br/>(sub: repo:org/repo:ref:refs/heads/main)
    OIDC-->>GHA: Signed JWT
    GHA->>WIF: Exchange JWT for GCP credential
    WIF->>STS: Validate subject matches<br/>attribute condition
    STS-->>GHA: Short-lived access token
    GHA->>SA: Impersonate SA with token
    SA-->>GHA: SA credentials (1-hour lifetime)
    GHA->>GHA: Run terraform plan/apply
```

The `attribute.repository` and `attribute.ref` conditions ensure that only workflows running from the configured repo and `main` branch can impersonate the Terraform SA. Pull request workflows receive read-only permissions via a separate condition.

---

## Subnet Layout

Each spoke environment gets two subnets within the configured VPC CIDR:

| Subnet | Purpose | CIDR (example for 10.128.0.0/16) |
|--------|---------|-----------------------------------|
| `{prefix}-private` | Application workloads | `10.128.0.0/20` |
| `{prefix}-database` | Cloud SQL, Memorystore | `10.128.16.0/20` |

Secondary IP ranges for GKE pods and services are allocated within the private subnet when `enable_gke = true`.

All subnets have VPC Flow Logs enabled and export to BigQuery via the Cloud Audit Logs sink.

---

## DNS Resolution Chain

```mermaid
graph LR
    vm["VM in Spoke\n(resolves *.internal.example.com)"]
    private_dns["Private DNS Zone\n(hub project)"]
    peering["DNS Peering\n(hub → spoke)"]
    cloud_dns["Cloud DNS\nResolver 169.254.169.254"]

    vm --> cloud_dns
    cloud_dns --> peering
    peering --> private_dns
    private_dns -->|"A record"| vm
```

Spoke projects use DNS peering to resolve records from the hub's private zone. No split-horizon or on-premises DNS forwarder configuration is included by default; add forwarding targets to `var.forwarding_targets` in the dns module if needed.

---

## Reference: Key Network Variables

| Variable | Module | Description |
|----------|--------|-------------|
| `vpc_cidr_block` | `modules/host` | VPC address space — must not overlap other VPCs. Required; no default. |
| `psa_prefix_length` | `modules/host` | Private Service Access prefix (16–29). Controls Cloud SQL connectivity range. |
| `vpn_tunnel_count` | `modules/host` | Number of HA-VPN tunnels (1 or 2). Must be 2 for 99.99% SLA. |
| `enable_interconnect` | `modules/host` | Provision Dedicated Interconnect VLAN attachment. |
| `vpc_service_controls` | `modules/host` | Object controlling VPC-SC perimeter config. |
