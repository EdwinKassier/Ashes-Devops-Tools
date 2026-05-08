# Cloud Armor Example

A production-ready Cloud Armor WAF policy with OWASP managed rules, Log4Shell
protection, adaptive protection (ML-based), and a custom IP-block rule.

## What this creates

| Resource | Notes |
|----------|-------|
| `google_compute_security_policy` | WAF policy attached to an external LB backend |
| OWASP managed rules (sensitivity 2) | CRS-based ruleset — blocks SQLi, XSS, RCE, etc. |
| Log4Shell WAF rule (priority 999) | Blocks CVE-2021-44228 JNDI payloads |
| Adaptive protection | ML-based anomaly detection; set `enable_adaptive_protection = true` in prod |
| Custom IP-block rule | Denies a specific CIDR — replace with your blocklist |

## Prerequisites

- A GCP project with the **Cloud Armor** API enabled (`compute.googleapis.com`).
- An external HTTPS load balancer with a backend service to attach the policy to.
  The `policy_id` output provides the resource ID to reference in the LB backend.

## Usage

```bash
# 1. Edit main.tf — set project_id and update the custom_rules CIDR block
# 2. Initialise
terraform -chdir=examples/cloud-armor init

# 3. Plan
terraform -chdir=examples/cloud-armor plan

# 4. Apply
terraform -chdir=examples/cloud-armor apply
```

## Attach to a backend service

```hcl
resource "google_compute_backend_service" "api" {
  # ... other config ...
  security_policy = module.cloud_armor.policy_id
}
```

## Customisation

| Variable | What to change |
|----------|---------------|
| `owasp_sensitivity` | Lower (1) = fewer false positives; higher (4) = stricter blocking |
| `enable_adaptive_protection` | Set `true` in production once baseline traffic is established |
| `custom_rules` | Add CIDRs, country-based rules, or header-based conditions |
| `default_rule_action` | Change to `"deny(403)"` for an allowlist model |

## Cost note

Cloud Armor charges **per policy per month** plus per-request fees. Adaptive
protection adds an additional per-policy charge. See the
[Cloud Armor pricing page](https://cloud.google.com/armor/pricing) before enabling
in many projects.
