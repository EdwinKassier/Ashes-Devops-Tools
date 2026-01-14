# Development Environment (DEV)

## Purpose
The **Development** environment is a sandbox for engineering teams to iterate on features, test new infrastructure configurations, and experiment with Google Cloud services.

## Constraints
- **SLA**: Best Effort. No uptime guarantees.
- **Data**: Mock data only. No PII or customer data allowed.
- **Access**: Broad access for developers (Engineering Group).

## Configuration
| Feature | Setting | Rationale |
| :--- | :--- | :--- |
| **Budget** | $500/month | Limit financial blast radius of experiments. |
| **Flow Logs** | 10% Sampling | Reduce logging costs while maintaining basic visibility. |
| **Log Retention** | 30 Days | Sufficient for immediate debugging. |
| **Deletion Protection** | Disabled | Allow easy tear-down and recreation of resources. |
| **Cloud Armor** | Disabled | Not required for internal/non-critical workloads. |

## Network
- **VPC Name**: `my-org-dev-vpc`
- **CIDR**: `10.10.0.0/16` (derived)
- **Hub Connectivity**: Peered to `hub-vpc` for shared services.
