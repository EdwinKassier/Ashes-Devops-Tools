# Runbook: CIDR Expansion

**When to use:** A subnet is exhausted (< 10% free IPs remaining), GKE secondary ranges need more space, or a new workload requires a larger address block.

**Time:** 1–4 hours (primarily waiting for workload drain if resizing a subnet used by running VMs).  
**Risk:** High — subnet recreation destroys and re-creates all resources in the subnet (VMs, Cloud SQL instances, PSA ranges). Plan carefully.  
**Prerequisites:** `enable_deletion_protection` must be set to `false` (or the guard resource removed from state) before any subnet destruction.

---

## Important: Terraform Will Destroy Subnets

GCP does not support resizing a subnet's primary CIDR range in-place. Any change to `ip_cidr_range` in the subnet module **will plan a destroy-then-recreate** cycle. This means:

- VMs in the subnet will be terminated during the apply
- Cloud SQL private IP connections will be severed and re-established
- NAT IP allocations will change
- Any hardcoded IP references in application config must be updated

**Alternative for secondary ranges:** GKE pod/service secondary ranges can be expanded without destroying the subnet. See the secondary range section below.

---

## Option A: Expand Secondary IP Ranges (GKE, no downtime)

Secondary IP ranges (used for GKE pods and services) can be added or expanded without subnet recreation.

### Step 1 — Verify current usage

```bash
gcloud compute networks subnets describe SUBNET_NAME \
  --region=REGION \
  --project=PROJECT_ID \
  --format="yaml(secondaryIpRanges)"
```

### Step 2 — Update the secondary range in Terraform

In `envs/apps/main.tf` (or the relevant module call), update `secondary_ip_ranges`:

```hcl
secondary_ip_ranges = [
  {
    range_name    = "gke-pods"
    ip_cidr_range = "10.200.0.0/14"   # expanded from /16
  },
  {
    range_name    = "gke-services"
    ip_cidr_range = "10.204.0.0/20"
  }
]
```

### Step 3 — Plan and verify no primary CIDR change

```bash
make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars
```

The plan must show `~ update in-place` for the subnet, not `- destroy` + `+ create`. If it shows destroy, stop and re-examine the change.

### Step 4 — Apply

```bash
terraform -chdir=envs/apps apply -target=module.host.module.private_subnets -var-file=examples/dev.tfvars
```

---

## Option B: Replace Primary CIDR (requires downtime)

### Step 1 — Schedule a maintenance window

Notify workload owners. All VMs in the affected subnet will be terminated.

### Step 2 — Drain the subnet

Stop or live-migrate all VMs:

```bash
gcloud compute instances list \
  --filter="networkInterfaces.subnetwork:SUBNET_NAME" \
  --project=PROJECT_ID \
  --format="value(name,zone)"
```

Stop each VM or move it to a different subnet before proceeding.

### Step 3 — Remove deletion protection guard (if enabled)

If `enable_deletion_protection = true`, the plan will be blocked by the guard resource. Remove it from state first:

```bash
# Find the guard resource address
terraform -chdir=envs/apps state list | grep deletion_protection_guard

# Remove from state (this does NOT destroy the resource, just removes Terraform's tracking)
terraform -chdir=envs/apps state rm 'module.host.terraform_data.deletion_protection_guard[0]'
```

After the CIDR change is applied, re-enable deletion protection by setting `enable_deletion_protection = true` and applying again.

### Step 4 — Update the CIDR in Terraform

Choose a new CIDR from your IPAM that does not overlap any existing VPC:

```hcl
# In examples/dev.tfvars
vpc_cidr_block = "10.130.0.0/16"   # new, larger block
```

> **Note:** `vpc_cidr_block` is required and has no default. There is no CIDR hash fallback — the value you set is exactly what gets deployed. Coordinate with your network team to allocate a non-overlapping block.

### Step 5 — Plan with destroy preview

```bash
make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars 2>&1 | grep -E "will be (destroyed|created|updated)"
```

Confirm the plan destroys only the subnet resources, not the project or VPC.

### Step 6 — Apply

```bash
terraform -chdir=envs/apps apply -var-file=examples/dev.tfvars
```

### Step 7 — Restore workloads

Restart VMs and verify connectivity:

```bash
# Verify new subnet CIDR
gcloud compute networks subnets describe SUBNET_NAME \
  --region=REGION --project=PROJECT_ID \
  --format="value(ipCidrRange)"

# Verify NAT is routing
gcloud compute routers get-nat-mapping-info ROUTER_NAME \
  --region=REGION --project=PROJECT_ID
```

### Step 8 — Re-enable deletion protection

```hcl
# In your tfvars or module call
enable_deletion_protection = true
```

```bash
terraform -chdir=envs/apps apply -target=module.host.terraform_data.deletion_protection_guard -var-file=examples/dev.tfvars
```
