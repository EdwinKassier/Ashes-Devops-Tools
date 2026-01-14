# User Acceptance Testing Environment (UAT)

## Purpose
The **UAT** (User Acceptance Testing) environment mimics Production configuration to allow business owners and QA teams to validate releases before they go live.

## Constraints
- **SLA**: Business Hours Support.
- **Data**: Anonymized/scrubbed production data.
- **Access**: QA Team and Business Owners.

## Configuration
| Feature | Setting | Rationale |
| :--- | :--- | :--- |
| **Budget** | $1000/month | Sufficient for full-scale load testing. |
| **Flow Logs** | 50% Sampling | Balance between visibility and cost. |
| **Log Retention** | 60 Days | Cover the length of a typical release cycle. |
| **Deletion Protection** | Disabled | Flexibility to reset environment between test cycles. |
| **Cloud Armor** | Disabled | Not typically exposed to public attack vectors during testing. |

## Network
- **VPC Name**: `my-org-uat-vpc`
- **CIDR**: `10.30.0.0/16` (derived)
- **Hub Connectivity**: Peered to `hub-vpc` for shared services.
