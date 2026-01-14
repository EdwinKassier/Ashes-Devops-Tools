# Production Environment (PROD)

## Purpose
The **Production** environment hosts live, customer-facing applications and critical business data. Stability, security, and integrity are the primary goals.

## Constraints
- **SLA**: High Availability (99.9%+).
- **Data**: Real customer data (PII). Strict access controls apply.
- **Access**: Restricted. CI/CD only for changes. Read-only for authorized ops personnel.

## Configuration
| Feature | Setting | Rationale |
| :--- | :--- | :--- |
| **Budget** | $5000/month | Accommodate scale. Alerting at 50%, 75%, 90%. |
| **Flow Logs** | 100% Sampling | Full fidelity for security forensics and compliance. |
| **Log Retention** | 365 Days | Meet compliance requirements (e.g., SOC2, ISO). |
| **Deletion Protection** | **Enabled** | Prevent accidental deletion of critical infrastructure. |
| **Cloud Armor** | **Enabled** | WAF active with OWASP Top 10 protection. |

## Network
- **VPC Name**: `my-org-prod-vpc`
- **CIDR**: `10.20.0.0/16` (derived)
- **Hub Connectivity**: Peered to `hub-vpc` for shared services.
