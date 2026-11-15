# WS2 Data plane works as a system: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or build to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the default data plane work end to end on both clouds. AWS spoke VPCs get the CIDR their subnets are cut from, in any region, with egress and DNS that reach the spokes. GCP spokes resolve the internal zone and reach on-premises. The application runtimes start healthy and scale in production.

**Architecture:** Every fix lands in the existing module or stage that owns the behaviour, and the roots only resolve config. No change replaces an existing VPC, subnet, zone or peering: each shape change is either a no-op for an existing estate (proven by `ignore_changes`, `moved` blocks or count-gating of resources that could never have been created), or opt-in with a documented migration in `UPGRADING.md`. Mock tests prove the plan shape; the "Sandbox proof" section lists the live check that proves each task.

**Tech Stack:** Terraform 1.17.1, hashicorp/aws `>= 6.46.0, < 7.0.0`, google `~> 8.0`, `terraform test` with `mock_provider` / `override_module` / `override_data`, HCP Terraform, OPA (`policies/opa-destructive/destroy_guard.rego`).

**Conventions used in every task**

- `TF=/private/tmp/claude-501/-Users-edwinkassier-Desktop-Ashes-Ashes-Devops-Tools--claude-worktrees-enterprise-devops-audit-949b65/50c7eb6b-1026-4421-925b-256b9cc0fb04/scratchpad/tf/terraform` (the local brew Terraform is too old).
- Run tests with `make test TEST_DIRS="<dir> [<dir>...]" TERRAFORM=$TF`.
- After any variable or output change run `make docs`. Before each commit run `make fmt-check consistency count-check links` and, when a config key changes, `make config-check`.
- A `feat!:` or `fix!:` commit must add an `UPGRADING.md` entry under `## Unreleased` (CI enforces it). Every task also adds one bullet to `CHANGELOG.md` under `## [Unreleased]` in a new `### WS2 data plane (2026-11-11 due-diligence audit)` section (create it in Task 1).

## Findings covered

| Finding | Severity | Task(s) |
|---|---|---|
| ARC-1 | Critical | 1, 2, 3 |
| ARC-2 | Critical | 4 |
| ARC-3 | Critical | 5, 6 |
| ARC-6 | High | 7, 8, 9 |
| ARC-21 | Medium | 7 |
| ARC-10 | High | 10 |
| ARC-11 | Medium | 11 |
| ARC-4 | High | 3, 12, 13 |
| ARC-5 | High | 14 |
| ARC-12 | Medium | 15 |
| ARC-16 | Medium | 16, 17 |

## What the code already has (checked before planning)

- `modules/aws/network/vpc` already supports `ipam_allocation = "explicit_cidr"` (`main.tf:81-99`), and the workload stage and root expose it as the opt-in `ipam_explicit_cidr` (default `false`). The hub VPCs already use `explicit_cidr`, but only when listed in `ipam_new_vpcs` (`stages/network-hub/main.tf:92-102`), so by default they are static and absent from the pool. Task 1 flips the default safely; Task 2 registers the static hubs. Nothing new is invented.
- `envs/gcp/workload/outputs.tf:51-54` already outputs `hub_peering_state`, and `envs/gcp/network-hub/data.tf:34-42` documents the second pass. Task 14 adds the missing runbook step, a warning check and a limit guard on top.
- `modules/gcp/network/dns` already supports `forwarding_targets` and `private_visibility_networks`; `modules/gcp/stages/dns-anchor` already has `additional_visibility_networks`. Tasks 4 and 15 reuse them.
- `aws-cidr-expansion.md` and `cidr-expansion.md` already cover per-VPC growth. Task 12 adds the missing pool-level lever.

## Defects found while reading the code (in scope, fixed here)

1. `modules/aws/network/route53-resolver/variables.tf:22-42` defaults `subnet_ids = ["subnet-aaaa", "subnet-bbbb"]` and `security_group_ids = ["sg-aaaaaaaaaaaaaaaaa"]`, and `stages/network-hub/main.tf:446-456` never passes `security_group_ids`. The resolver endpoints therefore reference a placeholder security group, so the first real `aws-network` apply fails. (Task 7.)
2. `modules/aws/network/vpc-endpoints` gets no `security_group_ids` from the hub (`stages/network-hub/main.tf:430-440`), so the interface endpoints use the egress VPC default security group, which the vpc module strips to deny-all (`vpc/main.tf:121-125`). The endpoints accept no traffic, even from the egress VPC. (Task 8.)
3. Creating a DNS peering zone needs `dns.networks.targetWithPeeringZone` (`roles/dns.peer`) on the target network's project. The workload apply SAs hold roles only on their own environment folder (`stages/projects/main.tf:83-95`, `stages/bootstrap/variables.tf:196-246`), so the `internal-peering` zone that targets the hub VPC in `shared-hub` is SUSPECTED to fail with 403. (Task 4.)

## Decisions needed

- **D1 (ARC-2): how spokes reach the internal zone.** Option A: bind the hub VPC to the `internal-root` zone (add it to the zone's visibility). Option B: point every spoke's peering zone at the DNS anchor VPC. **Recommendation: A.** It is one change in `gcp-network-hub`, no workload root changes, no contract change, and the hub VPC can then answer on-premises queries through the inbound policy in Task 15 (DNS peering is not transitive, so B would need a second peering zone on the hub for hybrid). The anchor stays the zone owner. Task 4 implements A.
- **D2 (ARC-1): flip the IPAM default.** Recommendation: flip `explicit_cidr` to the default for every VPC (new and existing). Task 1 adds `ignore_changes = [ipv4_netmask_length]`, so an existing netmask VPC whose allocated block equals `vpc_cidr` plans no change. A VPC whose allocated block differs is already broken (its subnets cannot exist); its migration is to set `vpc_cidr` to the allocated block. The alternative is to keep the opt-in and only document it, which leaves ARC-1 open for every new estate.
- **D3 (ARC-5): the second `gcp-network-hub` run.** A reverse run trigger `gcp-workload-<env> -> gcp-network-hub` would remove the manual step but creates a trigger cycle in the DAG that tfc-admin builds (`envs/tfc-admin/main.tf:1386-1418`). Recommendation: keep the manual run, make it a numbered runbook step, and add a post-apply `check` that warns while the spoke side is `INACTIVE`. NCC (`gcp.network.connectivity: ncc`) stays opt-in.
- **D4 (ARC-10): starter egress is not inspected.** Recommendation: in `starter` (no Network Firewall) route spoke `0.0.0.0/0` straight to the egress attachment, so spokes get NAT egress without inspection. The alternative is to forbid spokes in `starter`, which is today's behaviour and is what the finding reports. The owner must accept that `starter` means uninspected egress.
- **D5 (ARC-6): spoke traffic to interface endpoints stays inspected.** A TGW route that sends `egress_cidr` from the spoke tables straight to the egress attachment would make return traffic asymmetric (the shared table returns spoke traffic through inspection), which the stateful firewall drops. Recommendation: keep inspection on this path and record the per-GB processing cost in `docs/known-gaps.md` (Task 8).

---

### Task 1: Explicit-CIDR IPAM allocation by default, safe for existing VPCs (ARC-1)

**Files:**
- Modify: `modules/aws/network/vpc/main.tf:17-24` (header comment), `:81-99` (`aws_vpc.this`)
- Modify: `modules/aws/network/vpc/variables.tf:31-41` (`ipam_allocation`)
- Modify: `modules/aws/network/vpc/tests/plan_assertions.tftest.hcl:184-197` (`existing_ipam_vpc_keeps_netmask_shape`)
- Modify: `modules/aws/stages/workload/variables.tf:76-81` (`ipam_explicit_cidr`), `modules/aws/stages/workload/main.tf:100-105`
- Modify: `modules/aws/stages/workload/tests/spoke_routing.tftest.hcl:89-115`
- Modify: `envs/aws/workload/variables.tf:67-72` (`ipam_explicit_cidr`)
- Modify: `UPGRADING.md` (`## Unreleased` > `### AWS`), `CHANGELOG.md`, `docs/runbooks/aws-cidr-expansion.md:25-27`

- [ ] **Step 1: Write the failing tests.** Replace the run `existing_ipam_vpc_keeps_netmask_shape` in `modules/aws/network/vpc/tests/plan_assertions.tftest.hcl` with:

```hcl
run "ipam_default_is_explicit_cidr" {
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    ipam_pool_id             = "ipam-pool-0123456789abcdef0"
    cidr_block               = "10.72.0.0/16"
  }

  assert {
    condition     = aws_vpc.this.ipv4_ipam_pool_id == "ipam-pool-0123456789abcdef0" && aws_vpc.this.cidr_block == "10.72.0.0/16" && aws_vpc.this.ipv4_netmask_length == null
    error_message = "An IPAM VPC must request exactly cidr_block from the pool by default, so the subnets cut from cidr_block fit the VPC."
  }

  assert {
    condition     = aws_subnet.this["private-eu-west-2a"].cidr_block == "10.72.8.0/24"
    error_message = "Subnets must be cut from the same block the pool allocates."
  }
}

run "legacy_netmask_still_selectable" {
  command = plan

  variables {
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
    ipam_pool_id             = "ipam-pool-0123456789abcdef0"
    ipam_allocation          = "netmask"
    cidr_block               = "10.20.0.0/16"
  }

  assert {
    condition     = aws_vpc.this.ipv4_netmask_length == 16 && aws_vpc.this.cidr_block == null
    error_message = "ipam_allocation = netmask must keep the legacy pool + netmask_length shape."
  }
}
```

In `modules/aws/stages/workload/tests/spoke_routing.tftest.hcl` replace the runs `ipam_default_plans_legacy_netmask_shape` and `ipam_explicit_cidr_is_opt_in` with:

```hcl
run "ipam_default_is_explicit_cidr" {
  command = plan

  variables {
    ipam_pool_id = "ipam-pool-0123456789abcdef0"
  }

  assert {
    condition     = local.ipam_allocation == "explicit_cidr"
    error_message = "The spoke must request vpc_cidr explicitly from the pool by default (ARC-1)."
  }
}

run "ipam_legacy_netmask_is_opt_out" {
  command = plan

  variables {
    ipam_pool_id       = "ipam-pool-0123456789abcdef0"
    ipam_explicit_cidr = false
  }

  assert {
    condition     = local.ipam_allocation == "netmask"
    error_message = "ipam_explicit_cidr = false must keep the legacy netmask shape."
  }
}
```

- [ ] **Step 2: Run and confirm the failure.** `make test TEST_DIRS="modules/aws/network/vpc modules/aws/stages/workload" TERRAFORM=$TF`. Expected: `ipam_default_is_explicit_cidr` fails in both suites (`ipv4_netmask_length == 16`, `local.ipam_allocation == "netmask"`).

- [ ] **Step 3: Implement.** In `modules/aws/network/vpc/variables.tf` change `ipam_allocation`:

```hcl
variable "ipam_allocation" {
  description = "How an IPAM VPC obtains its CIDR: explicit_cidr (default: pool + cidr_block, so the pool allocates exactly the block the subnets are cut from) or netmask (legacy: pool + netmask_length). Switching an existing netmask VPC to explicit_cidr is a no-op when cidr_block equals the block IPAM allocated (ipv4_netmask_length is ignored after create); otherwise set cidr_block to the allocated block first. Ignored when ipam_pool_id is empty."
  type        = string
  default     = "explicit_cidr"
  nullable    = false

  validation {
    condition     = contains(["netmask", "explicit_cidr"], var.ipam_allocation)
    error_message = "ipam_allocation must be netmask or explicit_cidr."
  }
}
```

In `modules/aws/network/vpc/main.tf` replace lines 81-99 with:

```hcl
resource "aws_vpc" "this" {
  # Three shapes:
  #   * static (no pool)                    - cidr_block only.
  #   * IPAM, ipam_allocation = explicit_cidr (default) - pool + cidr_block, so the
  #     pool allocates exactly the block the subnet math assumes.
  #   * IPAM, ipam_allocation = netmask (legacy) - pool + ipv4_netmask_length.
  ipv4_ipam_pool_id   = var.ipam_pool_id != "" ? var.ipam_pool_id : null
  ipv4_netmask_length = var.ipam_pool_id != "" && var.ipam_allocation == "netmask" ? var.netmask_length : null
  cidr_block          = var.ipam_pool_id == "" || var.ipam_allocation == "explicit_cidr" ? var.cidr_block : null

  assign_generated_ipv6_cidr_block = var.enable_ipv6
  enable_dns_support               = true
  enable_dns_hostnames             = true

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # ipv4_netmask_length is only read at create. Ignoring it lets an existing
    # netmask-mode VPC move to explicit_cidr without replacement: its state
    # cidr_block already equals the allocated block, so only this create-time
    # argument would differ.
    ignore_changes = [ipv4_netmask_length]
  }
}

# Post-apply guard: an IPAM block that differs from cidr_block means the subnet
# math is wrong (ARC-1). Unknown at plan in netmask mode, so it reports after apply.
check "ipam_allocation_matches_subnet_math" {
  assert {
    condition     = var.ipam_pool_id == "" || aws_vpc.this.cidr_block == var.cidr_block
    error_message = "VPC ${var.name} holds ${aws_vpc.this.cidr_block} from IPAM, but its subnets are cut from cidr_block ${var.cidr_block}. Set cidr_block (vpc_cidr) to the allocated block; see UPGRADING.md (IPAM explicit-CIDR default)."
  }
}
```

Update the header comment at `main.tf:17-24` to say explicit_cidr is the default. In `modules/aws/stages/workload/variables.tf` and `envs/aws/workload/variables.tf` change `ipam_explicit_cidr` to `default = true` with this description: `"When ipam_pool_id is set, request vpc_cidr explicitly from the pool (default true). false keeps the legacy pool + netmask_length shape. An existing netmask VPC plans no change when vpc_cidr equals its allocated block (see UPGRADING.md)."` In `modules/aws/stages/workload/main.tf:100-105` change the comment to `# explicit_cidr unless the caller opts back into the legacy netmask shape.`

- [ ] **Step 4: Run and confirm the pass.** `make test TEST_DIRS="modules/aws/network/vpc modules/aws/stages/workload envs/aws/workload modules/aws/stages/network-hub envs/aws/network" TERRAFORM=$TF`. Expected: all pass.

- [ ] **Step 5: Docs.** `make docs`. In `UPGRADING.md` under `## Unreleased` > `### AWS` add `#### Spoke VPCs request their CIDR explicitly from IPAM (aws-workload)` with these steps: (1) for each existing `aws-workload-<env>`, run `terraform state show 'module.aws_workload.module.vpc.aws_vpc.this'` in a speculative plan or the TFC state viewer and read `cidr_block`; (2) if it differs from `vpc_cidr`, set `aws.workload_environments.<env>.vpc_cidr` to that block before you apply (the subnets were never created, so this only fixes the math); (3) if you must keep the old shape, set `ipam_explicit_cidr = false`. In `docs/runbooks/aws-cidr-expansion.md:25-27` replace "(`ipv4_ipam_pool_id` + `ipv4_netmask_length` ...)" with "(`ipv4_ipam_pool_id` + `cidr_block`, the explicit-CIDR default)". Add the CHANGELOG bullet "**Spoke VPCs get the CIDR their subnets use (ARC-1).**".

- [ ] **Step 6: Commit.** `git commit -m "fix(aws-network)!: request the spoke VPC CIDR explicitly from IPAM by default"`

---

### Task 2: Reserve the static hub VPC CIDRs in the IPAM pool (ARC-1)

**Files:**
- Modify: `modules/aws/stages/network-hub/main.tf:92-102` (hub pool locals; add the reservation after it)
- Modify: `modules/aws/stages/network-hub/outputs.tf` (new output)
- Modify: `modules/aws/stages/network-hub/tests/plan_assertions.tftest.hcl` (new runs)

- [ ] **Step 1: Write the failing test.** Append to `modules/aws/stages/network-hub/tests/plan_assertions.tftest.hcl` (it already overrides `module.ipam` with `regional_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" }`):

```hcl
run "static_hub_vpcs_are_reserved_in_the_pool" {
  command = plan

  assert {
    condition = (
      length(aws_vpc_ipam_pool_cidr_allocation.hub_static) == 2 &&
      aws_vpc_ipam_pool_cidr_allocation.hub_static["inspection"].cidr == var.inspection_cidr &&
      aws_vpc_ipam_pool_cidr_allocation.hub_static["egress"].cidr == var.egress_cidr &&
      aws_vpc_ipam_pool_cidr_allocation.hub_static["egress"].ipam_pool_id == "ipam-pool-eu-west-2-0"
    )
    error_message = "Static hub VPCs must hold a manual allocation in the regional pool so IPAM never hands their range to a spoke."
  }
}

run "pool_allocated_hub_vpc_needs_no_reservation" {
  command = plan

  variables {
    ipam_new_vpcs = ["egress"]
  }

  assert {
    condition     = keys(aws_vpc_ipam_pool_cidr_allocation.hub_static) == ["inspection"]
    error_message = "A hub VPC that allocates from the pool is its own allocation; only static hubs are reserved."
  }
}
```

- [ ] **Step 2: Run.** `make test TEST_DIRS=modules/aws/stages/network-hub TERRAFORM=$TF`. Expected failure: `Reference to undeclared resource aws_vpc_ipam_pool_cidr_allocation.hub_static`.

- [ ] **Step 3: Implement.** After the `locals` block at `main.tf:92-102` add:

```hcl
# A static hub VPC (not created from the pool) still sits inside the regional
# pool CIDR. Without a manual allocation IPAM could allocate its range to a
# spoke (ARC-1). The allocation only reserves address space: it never touches
# the VPC, so it is safe on an existing estate. Keyed by plan-known names;
# the pool id itself is apply-time on a first run.
resource "aws_vpc_ipam_pool_cidr_allocation" "hub_static" {
  for_each = {
    for name, cidr in { inspection = var.inspection_cidr, egress = var.egress_cidr } : name => cidr
    if contains(keys(var.regional_cidrs), var.aws_region) && var.ipam_mode_for_new_vpcs_only && !contains(var.ipam_new_vpcs, name)
  }

  ipam_pool_id = local.hub_regional_pool_id
  cidr         = each.value
  description  = "Reserved for the static ${each.key} hub VPC (aws-network)."

  # The regional pool must have its CIDR provisioned before an allocation.
  depends_on = [module.ipam]
}
```

Add to `outputs.tf`:

```hcl
output "hub_static_ipam_allocations" {
  description = "Map of static hub VPC name (inspection, egress) to the CIDR reserved for it in the regional IPAM pool. Empty for hub VPCs created from the pool."
  value       = { for k, a in aws_vpc_ipam_pool_cidr_allocation.hub_static : k => a.cidr }
}
```

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/aws/stages/network-hub envs/aws/network" TERRAFORM=$TF`. Expected: pass.

- [ ] **Step 5: Docs.** `make docs`. In `docs/architecture/cidr-plan.md` under `## AWS` add a sentence: "The inspection and egress VPCs keep their static CIDRs; aws-network reserves both blocks in the regional pool (`hub_static_ipam_allocations`), so IPAM never allocates them to a spoke." CHANGELOG bullet. No UPGRADING entry (additive, no state move).

- [ ] **Step 6: Commit.** `git commit -m "fix(aws-network): reserve the static hub VPC CIDRs in the regional IPAM pool"`

---

### Task 3: tfc-admin address plan: unique workload CIDRs inside the regional pool (ARC-1, ARC-4)

With explicit allocation, two workloads that both fall back to `10.72.0.0/16` collide in IPAM, and a `vpc_cidr` outside the regional pool CIDR fails at apply. tfc-admin already checks overlaps (`envs/tfc-admin/config.tf:168-225`); it skips workloads without `vpc_cidr` and only checks `top_cidr`.

**Files:**
- Modify: `envs/tfc-admin/config.tf:184-225`
- Modify: `envs/tfc-admin/main.tf:978-981` (precondition)
- Modify: `envs/tfc-admin/tests/config.tftest.hcl:313-366`
- Modify: `envs/tfc-admin/tests/fixtures/landing-zone.yaml:19-21`
- Create: `envs/tfc-admin/tests/fixtures/landing-zone-cidr-pool.yaml`

- [ ] **Step 1: Write the failing test.** Create `envs/tfc-admin/tests/fixtures/landing-zone-cidr-pool.yaml`:

```yaml
# Test fixture: two workloads on the built-in vpc_cidr, one outside the regional pool (config.tftest.hcl).
version: 1
org:
  regions: {aws: eu-west-2}
  tfc:
    organization: cfg-tfc
    project_name_prefix: lz-
    aws_project: aws-landing-zone
    plan: standard
    vcs_repo:
      identifier: cfg/landing-zone
      github_app_installation_id: ghain-123
aws:
  enabled: true
  network:
    regional_cidrs: {eu-west-2: 10.64.0.0/12}
  workload_environments:
    dev: {account_key: workload_dev}
    staging: {account_key: workload_staging, is_production: true}
    perf: {account_key: workload_perf, vpc_cidr: 10.96.0.0/16}
```

Append to `envs/tfc-admin/tests/config.tftest.hcl`:

```hcl
run "workloads_sharing_the_default_vpc_cidr_fail_the_plan" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-cidr-pool.yaml"
  }

  assert {
    condition     = contains(local.cidr_overlaps, "aws.workload_environments.dev.vpc_cidr (10.72.0.0/16) overlaps aws.workload_environments.staging.vpc_cidr (10.72.0.0/16)")
    error_message = "A workload without vpc_cidr takes the built-in 10.72.0.0/16; two of them must be reported as an overlap."
  }

  assert {
    condition     = contains(local.cidr_outside_aws_pool, "aws.workload_environments.perf.vpc_cidr (10.96.0.0/16) is outside the eu-west-2 regional pool (10.64.0.0/12)")
    error_message = "A fixed AWS VPC range outside the home-region pool must be reported."
  }

  expect_failures = [terraform_data.input_contract]
}
```

Edit `envs/tfc-admin/tests/fixtures/landing-zone.yaml:19-21` so the clean fixture stays clean:

```yaml
  workload_environments:
    dev: {account_key: workload_dev, vpc_cidr: 10.72.0.0/16}
    staging: {account_key: workload_staging, is_production: true, vpc_cidr: 10.73.0.0/16}
```

- [ ] **Step 2: Run.** `make test TEST_DIRS=envs/tfc-admin TERRAFORM=$TF`. Expected failure: the overlap is not listed, and `local.cidr_outside_aws_pool` is undeclared.

- [ ] **Step 3: Implement.** In `envs/tfc-admin/config.tf` change the workload entry of `cidr_aws_ranges` (line 195) to fall back to the root default:

```hcl
      { for env, e in try({ for k, e in local.lz.aws.workload_environments : k => e }, {}) : "aws.workload_environments.${env}.vpc_cidr" => try(tostring(e.vpc_cidr), "10.72.0.0/16") },
```

Update the comment at lines 185-187 to: "A workload without vpc_cidr uses the aws-workload built-in 10.72.0.0/16, so two such workloads overlap and fail here." After `cidr_outside_aws_top` add:

```hcl
  # Explicit IPAM allocation (aws-workload default) fails at apply when the
  # block is outside the home-region pool, so check it here.
  cidr_aws_home_region = try(tostring(local.lz.org.regions.aws), "eu-west-2")
  cidr_aws_pool = local.enable_aws ? try(
    tostring(local.lz.aws.network.regional_cidrs[local.cidr_aws_home_region]),
    "10.64.0.0/12",
  ) : null
  cidr_outside_aws_pool = local.cidr_aws_pool == null || !can(cidrnetmask(coalesce(local.cidr_aws_pool, "x"))) ? [] : [
    for k, c in local.cidr_aws_ranges : "${k} (${c}) is outside the ${local.cidr_aws_home_region} regional pool (${local.cidr_aws_pool})"
    if tonumber(split("/", c)[1]) < tonumber(split("/", local.cidr_aws_pool)[1]) ||
    cidrhost("${split("/", c)[0]}/${split("/", local.cidr_aws_pool)[1]}", 0) != cidrhost(local.cidr_aws_pool, 0)
  ]
```

In `envs/tfc-admin/main.tf:978-981` replace the precondition with:

```hcl
    precondition {
      condition     = length(local.cidr_overlaps) == 0 && length(local.cidr_outside_aws_top) == 0 && length(local.cidr_outside_aws_pool) == 0
      error_message = "config/landing-zone.yaml address plan conflicts (docs/architecture/cidr-plan.md: GCP 10.0.0.0/12, AWS 10.64.0.0/10, one regional pool per region): ${join("; ", concat(local.cidr_overlaps, local.cidr_outside_aws_top, local.cidr_outside_aws_pool))}. Give every aws.workload_environments entry its own vpc_cidr inside aws.network.regional_cidrs.<org.regions.aws>."
    }
```

- [ ] **Step 4: Run.** `make test TEST_DIRS=envs/tfc-admin TERRAFORM=$TF`. Expected: pass. If another tfc-admin fixture lists two AWS workloads without `vpc_cidr`, give each a distinct `vpc_cidr` inside `10.64.0.0/12`; the scaffold fixtures under `tests/fixtures/scaffold/` already set `vpc_cidr` (checked: `landing-zone.aws.yaml:316-319`).

- [ ] **Step 5: Docs.** Extend `docs/architecture/cidr-plan.md` `## Enforcement` with two bullets: "a workload without `vpc_cidr` counts as `10.72.0.0/16`, so two such workloads overlap" and "a fixed AWS VPC range outside the home-region regional pool". In `config/landing-zone.example.yaml:313` change the comment `vpc_cidr is optional.` to `vpc_cidr is required once you have more than one workload (each needs its own block inside the regional pool).` CHANGELOG bullet. UPGRADING entry under `### HCP Terraform and policy`: "tfc-admin now fails when two AWS workloads share a `vpc_cidr` (including the built-in `10.72.0.0/16`) or a `vpc_cidr` is outside the home-region pool. Set a distinct `aws.workload_environments.<env>.vpc_cidr` for each."

- [ ] **Step 6: Commit.** `git commit -m "fix(tfc-admin)!: fail the plan on shared or out-of-pool AWS workload CIDRs"`

---

### Task 4: Spokes resolve the internal zone through the hub VPC (ARC-2, D1)

**Files:**
- Modify: `modules/gcp/stages/network-hub/main.tf:182-203` (`module "dns_anchor"`)
- Modify: `modules/gcp/stages/network-hub/tests/plan_assertions.tftest.hcl:60-75`
- Modify: `modules/gcp/stages/bootstrap/service_accounts.tf:239-259` (delegated network roles)
- Modify: `modules/gcp/stages/projects/main.tf:97-147` (new grant)
- Modify: `modules/gcp/stages/projects/outputs.tf:25-33` (`automation_folder_grants`)
- Modify: `modules/gcp/stages/projects/tests/automation_identity_grants.tftest.hcl` (new run)
- Modify: `modules/gcp/stages/bootstrap/tests/plan_assertions.tftest.hcl` (new run)
- Modify: `docs/architecture/network-topology.md:178-193`

- [ ] **Step 1: Write the failing tests.** In `modules/gcp/stages/network-hub/tests/plan_assertions.tftest.hcl` replace the second assert of `dns_zone_binds_to_dns_anchor_network_self_link` with:

```hcl
  assert {
    condition = toset([
      for n in module.dns_anchor.dns_zones["internal-root"].zone.private_visibility_config[0].networks : n.network_url
      ]) == toset([
      "projects/mock-dns-project/global/networks/dns-vpc-core",
      "projects/mock-hub-project/global/networks/hub-vpc-core",
    ])
    error_message = "internal-root must be visible to the DNS anchor VPC and to the hub VPC: spoke peering zones target the hub VPC, and DNS peering resolves only zones bound to the target network (ARC-2)."
  }
```

Append to `modules/gcp/stages/projects/tests/automation_identity_grants.tftest.hcl`:

```hcl
run "workload_apply_sas_can_target_the_hub_with_a_peering_zone" {
  command = plan

  assert {
    condition = (
      length(google_folder_iam_member.workload_dns_peer) == 2 &&
      alltrue([for k, m in google_folder_iam_member.workload_dns_peer : m.folder == "folders/100" && m.role == "roles/dns.peer" && strcontains(m.member, "-apply@")])
    )
    error_message = "Each workload apply SA needs roles/dns.peer on the shared folder (target of its DNS peering zone), and nothing else there."
  }
}
```

Append to `modules/gcp/stages/bootstrap/tests/plan_assertions.tftest.hcl` (reuse its file-level variables):

```hcl
run "projects_apply_may_delegate_dns_peer_on_the_shared_folder" {
  command = plan

  assert {
    condition     = contains(output.delegated_network_folder_roles, "roles/dns.peer")
    error_message = "gcp-projects grants roles/dns.peer to workload apply SAs on the shared folder, so the delegated allow-list must admit it."
  }
}
```

- [ ] **Step 2: Run.** `make test TEST_DIRS="modules/gcp/stages/network-hub modules/gcp/stages/projects modules/gcp/stages/bootstrap" TERRAFORM=$TF`. Expected: three failures (one network URL, undeclared `workload_dns_peer`, `roles/dns.peer` absent).

- [ ] **Step 3: Implement.** In `modules/gcp/stages/network-hub/main.tf` change the `internal-root` entry of `module "dns_anchor"`:

```hcl
  dns_zones = {
    "internal-root" = {
      dns_name       = "${var.internal_domain}."
      description    = "Root Internal Zone for Organization"
      dnssec_enabled = true
      # Spoke peering zones (gcp-workload-<env> internal-peering) target the hub
      # VPC. DNS peering answers only from zones bound to the target network,
      # so the hub VPC must see this zone (ARC-2). In-place update of the
      # zone's private_visibility_config.
      additional_visibility_networks = [module.hub.network_self_link]
    }
  }
```

In `modules/gcp/stages/bootstrap/service_accounts.tf:257` change `delegated_network_folder_roles` to:

```hcl
  # roles/dns.peer: gcp-projects grants it to each workload apply SA on the
  # shared folder, so the workload DNS peering zone can target the hub VPC.
  delegated_network_folder_roles = sort(setsubtract(toset(concat(local.effective_network_folder_roles.plan, local.effective_network_folder_roles.apply, ["roles/dns.peer"])), toset(local.non_delegable_folder_roles)))
```

In `modules/gcp/stages/projects/main.tf`, inside the `locals` block that ends at line 118, add:

```hcl
  # A DNS peering zone needs dns.networks.targetWithPeeringZone on the TARGET
  # network's project (roles/dns.peer). Each gcp-workload-<env> peering zone
  # targets the hub VPC in the shared folder. roles/dns.peer holds only that
  # permission and networks.get, so it changes nothing in the shared projects.
  workload_dns_peer_grants = {
    for env, sas in var.workload_service_accounts : env => {
      folder = var.folders[var.network_folder_key].id
      member = "serviceAccount:${sas.apply}"
    }
    if env != var.network_folder_key && contains(keys(var.folders), var.network_folder_key)
  }
```

After `google_folder_iam_member.network_sa_env_viewer` add:

```hcl
resource "google_folder_iam_member" "workload_dns_peer" {
  for_each = local.workload_dns_peer_grants

  folder = each.value.folder
  role   = "roles/dns.peer"
  member = each.value.member
}
```

In `modules/gcp/stages/projects/outputs.tf` add a fourth map to `automation_folder_grants`: `{ for k, v in local.workload_dns_peer_grants : "workload-dns-peer|${k}" => { folder = v.folder, role = "roles/dns.peer" } },` and extend its description with `"workload-dns-peer|<env>" (roles/dns.peer on the shared folder)`.

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/gcp/stages/network-hub modules/gcp/stages/projects modules/gcp/stages/bootstrap envs/gcp/network-hub envs/gcp/projects envs/gcp/organization envs/gcp/bootstrap" TERRAFORM=$TF`. Expected: pass. Check that `organization`'s delegation tests still pass: the shared-folder condition now lists `roles/dns.peer`.

- [ ] **Step 5: Docs.** Replace the mermaid block and paragraph at `docs/architecture/network-topology.md:178-193` with: spoke VM, then Cloud DNS in the spoke VPC, then the `internal-peering` zone (target: hub VPC), then the `internal-root` zone in the DNS project, bound to `dns-vpc-core` and `hub-vpc-core`. State: "DNS peering is not transitive. The zone is bound to the hub VPC because every spoke peering zone targets the hub VPC. Each workload apply SA holds `roles/dns.peer` on the shared folder, which creating a peering zone needs." UPGRADING entry under `### GCP`: "Apply order for this release: `gcp-bootstrap`, `gcp-organization`, `gcp-projects`, then `gcp-network-hub`, then each `gcp-workload-<env>`. The zone change is in place." CHANGELOG bullet.

- [ ] **Step 6: Commit.** `git commit -m "fix(gcp-network)!: let spoke DNS peering resolve the internal root zone"`

---

### Task 5: The vpc module rejects availability zones from another region (ARC-3)

This turns the silent `InvalidParameterValue` at apply into a plan error for every caller, including direct consumers of the stage defaults.

**Files:**
- Modify: `modules/aws/network/vpc/main.tf` (`aws_vpc.this` lifecycle from Task 1)
- Modify: `modules/aws/network/vpc/outputs.tf` (new output)
- Modify: `modules/aws/network/vpc/tests/variables_validation.tftest.hcl` (new run)

- [ ] **Step 1: Write the failing test.** Append to `modules/aws/network/vpc/tests/variables_validation.tftest.hcl`:

```hcl
run "availability_zones_from_another_region_rejected" {
  command = plan

  variables {
    region                   = "us-east-1"
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
  }

  # The default availability_zones are eu-west-2a/b/c.
  expect_failures = [aws_vpc.this]
}

run "availability_zones_in_region_accepted" {
  command = plan

  variables {
    region                   = "us-east-1"
    availability_zones       = ["us-east-1a", "us-east-1b"]
    flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
  }

  assert {
    condition     = output.availability_zones == ["us-east-1a", "us-east-1b"]
    error_message = "The module must expose the availability zones it placed subnets in."
  }
}
```

- [ ] **Step 2: Run.** `make test TEST_DIRS=modules/aws/network/vpc TERRAFORM=$TF`. Expected: the first run fails (no error raised), the second fails (`output.availability_zones` undeclared).

- [ ] **Step 3: Implement.** In the `lifecycle` block of `aws_vpc.this` (Task 1) add:

```hcl
    precondition {
      condition     = alltrue([for az in local.azs : startswith(az, var.region)])
      error_message = "availability_zones ${jsonencode(local.azs)} are not all in region ${var.region}. Pass the region's zones (envs/aws/network and envs/aws/workload resolve them from aws.network.availability_zone_ids or the region)."
    }
```

Add to `outputs.tf`:

```hcl
output "availability_zones" {
  description = "Availability zone names the subnets are placed in (the first az_count entries of availability_zones), index-aligned with every per-tier list output."
  value       = local.azs
}
```

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/aws/network/vpc modules/aws/stages/workload modules/aws/stages/network-hub envs/aws/network envs/aws/workload tests/e2e/aws" TERRAFORM=$TF` (the e2e suite is skipped without credentials; the others must pass). A failing run means its fixture pairs a region with another region's zones: fix the fixture's `availability_zones`, never the precondition.

- [ ] **Step 5: Docs.** `make docs`. CHANGELOG bullet "**AZs from another region fail at plan (ARC-3).**". No UPGRADING entry: a plan that now fails would have failed at apply.

- [ ] **Step 6: Commit.** `git commit -m "fix(aws-network): reject availability zones outside the VPC region at plan"`

---

### Task 6: Roots resolve availability zones from AZ IDs or the region (ARC-3)

Resolution, explicit variable first: `availability_zones` (names) > `availability_zone_ids` (variable) > config IDs > the first three available zones of the region. IDs are mapped to names inside each account with `data.aws_availability_zones`, so the hub and the spokes land in the same physical AZs. An eu-west-2 estate on today's defaults resolves to `eu-west-2a`, `eu-west-2b` again, so it plans no change.

**Files:**
- Create: `envs/aws/network/azs.tf`, `envs/aws/workload/azs.tf`
- Modify: `envs/aws/network/variables.tf:120-145`, `envs/aws/network/main.tf:62-63`, `envs/aws/network/config.tf:21-64`
- Modify: `envs/aws/workload/variables.tf` (new variables after `ipam_explicit_cidr`), `envs/aws/workload/main.tf:96-120`, `envs/aws/workload/config.tf:21-59`
- Modify: every `mock_provider "aws" {}` without an alias in `envs/aws/network/tests/{config,root}.tftest.hcl` and `envs/aws/workload/tests/{app_golden_path,config,root,contracts}.tftest.hcl`
- Create: `envs/aws/network/tests/availability_zones.tftest.hcl`
- Modify: `config/landing-zone.schema.json` (`aws.network`, `aws.workload_environments.*`), `config/landing-zone.example.yaml:352-360` and `:314-328`

- [ ] **Step 1: Write the failing test.** Create `envs/aws/network/tests/availability_zones.tftest.hcl`:

```hcl
# AZ resolution for the network root (ARC-3).
mock_provider "aws" {}

variables {
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  log_archive_bucket_name  = "acme-org-log-archive"
  aws_region               = "us-east-1"
  aws_enabled_regions      = ["us-east-1"]
  regional_cidrs           = { us-east-1 = "10.64.0.0/12" }
  assume_role_arn          = "arn:aws:iam::666666666666:role/OrganizationAccountAccessRole"
  organization_contract = {
    organization_id       = "o-abc1234567"
    management_account_id = "111111111111"
    account_ids           = { network = "666666666666" }
  }
}

override_data {
  target = data.aws_availability_zones.available[0]
  values = {
    names    = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
    zone_ids = ["use1-az4", "use1-az6", "use1-az1", "use1-az2"]
  }
}

run "region_default_takes_the_first_available_zones" {
  command = plan

  assert {
    condition     = local.availability_zones == ["us-east-1a", "us-east-1b", "us-east-1c"]
    error_message = "With no names or IDs set, the root must use the region's first three available zones, not eu-west-2."
  }
}

run "zone_ids_map_to_this_accounts_names" {
  command = plan

  variables {
    availability_zone_ids = ["use1-az1", "use1-az4"]
  }

  assert {
    condition     = local.availability_zones == ["us-east-1c", "us-east-1a"]
    error_message = "AZ IDs must map to this account's zone names, in the given order."
  }
}

run "unknown_zone_id_fails_the_plan" {
  command = plan

  variables {
    availability_zone_ids = ["use1-az9", "use1-az4"]
  }

  expect_failures = [terraform_data.availability_zone_guard]
}

run "explicit_names_skip_the_lookup" {
  command = plan

  variables {
    availability_zones = ["us-east-1b", "us-east-1d"]
  }

  assert {
    condition     = length(data.aws_availability_zones.available) == 0 && local.availability_zones == ["us-east-1b", "us-east-1d"]
    error_message = "Explicit availability_zones must win and skip the data source."
  }
}
```

Copy the variable names from `envs/aws/network/tests/variables_validation.tftest.hcl:20-40` if any required input differs (that run already plans this root with an explicit contract). If Terraform rejects the file-level `override_data` in `explicit_names_skip_the_lookup` (its target has `count = 0` there), move the `override_data` block into the three runs that read the data source.

Add the same four runs (renamed for the workload root, asserting `local.availability_zones`) to a new `envs/aws/workload/tests/availability_zones.tftest.hcl`, using the file-level variables and `mock_provider` blocks of `envs/aws/workload/tests/contracts.tftest.hcl:1-30`, plus this run:

```hcl
run "environment_zone_ids_win_over_network_zone_ids" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-azs.yaml"
    environment              = "dev"
  }

  assert {
    condition     = local.availability_zone_ids == ["use1-az6", "use1-az4"]
    error_message = "aws.workload_environments.<env>.availability_zone_ids must win over aws.network.availability_zone_ids."
  }
}
```

with `envs/aws/workload/tests/fixtures/landing-zone-azs.yaml` containing `org.regions.aws: us-east-1`, `aws.network.availability_zone_ids: [use1-az1, use1-az4]`, and `aws.workload_environments.dev: {account_key: workload_dev, availability_zone_ids: [use1-az6, use1-az4]}` plus the `aws.contracts.{organization,security}` blocks copied from `envs/aws/workload/tests/fixtures/landing-zone.yaml`.

- [ ] **Step 2: Run.** `make test TEST_DIRS="envs/aws/network envs/aws/workload" TERRAFORM=$TF`. Expected failure: `Reference to undeclared resource data.aws_availability_zones.available`.

- [ ] **Step 3: Implement.** Create `envs/aws/network/azs.tf`:

```hcl
# Availability zones (ARC-3). Precedence: var.availability_zones (names) >
# var.availability_zone_ids > aws.network.availability_zone_ids > the region's
# first three available zones. AZ IDs name the same physical zone in every
# account, so the workload roots read the same config key and their spokes
# land in the hub's zones. Names are mapped inside THIS account.
locals {
  availability_zone_ids = (
    var.availability_zone_ids != null ? var.availability_zone_ids :
    local.cfg.availability_zone_ids != null ? local.cfg.availability_zone_ids : []
  )
  read_availability_zones = var.availability_zones == null
}

data "aws_availability_zones" "available" {
  count = local.read_availability_zones ? 1 : 0
  state = "available"

  # Only default-enabled zones: Local Zones and Wavelength need an opt-in.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  az_names_by_id = local.read_availability_zones ? zipmap(data.aws_availability_zones.available[0].zone_ids, data.aws_availability_zones.available[0].names) : {}
  unknown_az_ids = [for id in local.availability_zone_ids : id if !contains(keys(local.az_names_by_id), id)]
  availability_zones = (
    !local.read_availability_zones ? var.availability_zones :
    length(local.availability_zone_ids) > 0 ? [for id in local.availability_zone_ids : lookup(local.az_names_by_id, id, "unknown-${id}")] :
    slice(sort(data.aws_availability_zones.available[0].names), 0, min(3, length(data.aws_availability_zones.available[0].names)))
  )
}

resource "terraform_data" "availability_zone_guard" {
  lifecycle {
    precondition {
      condition     = length(local.unknown_az_ids) == 0
      error_message = "availability_zone_ids ${jsonencode(local.unknown_az_ids)} are not available zone IDs in ${local.aws_region} for this account (aws ec2 describe-availability-zones --region ${local.aws_region})."
    }
    precondition {
      condition     = var.az_count <= length(local.availability_zones)
      error_message = "az_count (${var.az_count}) exceeds the ${length(local.availability_zones)} resolved availability zones."
    }
  }
}
```

In `envs/aws/network/variables.tf` replace `availability_zones` (lines 120-129) and the second `az_count` validation (lines 141-144):

```hcl
variable "availability_zones" {
  description = "Availability zone NAMES for the hub VPCs, valid in this account only. Null (default) resolves them from availability_zone_ids, else aws.network.availability_zone_ids, else the region's first three available zones."
  type        = list(string)
  default     = null

  validation {
    condition     = var.availability_zones == null ? true : length(var.availability_zones) > 0
    error_message = "availability_zones must contain at least one zone."
  }
}

variable "availability_zone_ids" {
  description = "Availability zone IDs (e.g. euw2-az2), the same physical zones in every account. Null = aws.network.availability_zone_ids from config/landing-zone.yaml, else the region's first available zones. Setting IDs on an existing estate replaces subnets whose zone name changes: see UPGRADING.md."
  type        = list(string)
  default     = null

  validation {
    condition     = var.availability_zone_ids == null ? true : alltrue([for id in var.availability_zone_ids : can(regex("^[a-z]+[0-9]+-az[0-9]+$", id))])
    error_message = "availability_zone_ids entries must be AZ IDs such as euw2-az2 or use1-az4."
  }
}
```

and delete the `az_count <= length(var.availability_zones)` validation (the guard above replaces it). In `envs/aws/network/main.tf:62` pass `availability_zones = local.availability_zones` (the guard and the vpc precondition fail the plan before any bad zone reaches a resource). In `envs/aws/network/config.tf` add to `cfg`: `availability_zone_ids = try([for id in local.lz.aws.network.availability_zone_ids : tostring(id)], null)`.

Create `envs/aws/workload/azs.tf` with the same content except the ID precedence:

```hcl
  availability_zone_ids = (
    var.availability_zone_ids != null ? var.availability_zone_ids :
    try(local.cfg.workload_availability_zone_ids[local.environment], null) != null ? local.cfg.workload_availability_zone_ids[local.environment] :
    local.cfg.network_availability_zone_ids != null ? local.cfg.network_availability_zone_ids : []
  )
```

and with `var.az_count` in the second precondition. Add to `envs/aws/workload/variables.tf` the `availability_zones` and `availability_zone_ids` variables above (descriptions say "spoke VPC" and "aws.workload_environments.<env>.availability_zone_ids, else aws.network.availability_zone_ids") and:

```hcl
variable "az_count" {
  description = "Number of availability zones the spoke spreads each subnet tier across (1-3)."
  type        = number
  default     = 2
  nullable    = false

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "az_count must be between 1 and 3."
  }
}
```

Add to `envs/aws/workload/config.tf` `cfg`:

```hcl
    # Availability zone IDs: per environment, else the hub's (aws.network).
    workload_availability_zone_ids = { for env, e in try({ for k, v in local.lz.aws.workload_environments : k => v }, {}) : env => [for id in e.availability_zone_ids : tostring(id)] if try(e.availability_zone_ids, null) != null }
    network_availability_zone_ids  = try([for id in local.lz.aws.network.availability_zone_ids : tostring(id)], null)
```

In `envs/aws/workload/main.tf` add to `module "aws_workload"`: `availability_zones = local.availability_zones` and `az_count = var.az_count`.

Add to each unaliased `mock_provider "aws"` block listed under Files:

```hcl
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
      zone_ids = ["euw2-az2", "euw2-az3", "euw2-az1"]
    }
  }
}
```

A run in those files whose effective region is not eu-west-2 and that sets no `availability_zones` gets a run-level `override_data` for `data.aws_availability_zones.available[0]` with that region's names (Task 5's precondition names the run).

Schema: add to `aws.network.properties` and to `aws.workload_environments.additionalProperties.properties`:

```json
"availability_zone_ids": {
  "type": "array",
  "items": {"type": "string", "pattern": "^[a-z]+[0-9]+-az[0-9]+$"},
  "minItems": 1,
  "maxItems": 3,
  "description": "Availability zone IDs (aws ec2 describe-availability-zones), the same physical zones in every account. Unset = the region's first available zones."
}
```

Example config: under `aws.network` add `# availability_zone_ids: [euw2-az2, euw2-az3]   # AZ IDs, same physical zones in every account`.

- [ ] **Step 4: Run.** `make test TEST_DIRS="envs/aws/network envs/aws/workload" TERRAFORM=$TF`, then `make config-check`. Expected: pass.

- [ ] **Step 5: Docs.** `make docs`. UPGRADING entry under `### AWS`, `#### AWS availability zones follow the region and AZ IDs`: (1) an estate on the old defaults in eu-west-2 plans no change; (2) an estate that set `availability_zones` keeps them; (3) before you set `aws.network.availability_zone_ids` on an estate with workloads, plan each `aws-workload-<env>`: if a subnet would be replaced, set `aws.workload_environments.<env>.availability_zone_ids` to the IDs of its current zones (`aws ec2 describe-availability-zones` in that workload account). Update `docs/architecture/aws-landing-zone.md` (one paragraph: zones come from AZ IDs or the region). CHANGELOG bullet.

- [ ] **Step 6: Commit.** `git commit -m "feat(aws)!: resolve availability zones from AZ IDs or the region in every AWS network root"`

---

### Task 7: Route 53 resolver: a valid profile, gated endpoints, a real security group (ARC-6, ARC-21)

**Files:**
- Modify: `modules/aws/network/route53-resolver/main.tf:11-108`
- Modify: `modules/aws/network/route53-resolver/variables.tf:22-51` (add new variables after `forward_rules`)
- Modify: `modules/aws/network/route53-resolver/outputs.tf` (endpoint outputs)
- Modify: `modules/aws/network/route53-resolver/tests/plan_assertions.tftest.hcl`, `.../variables_validation.tftest.hcl`
- Modify: `modules/aws/stages/network-hub/main.tf:442-456`, `modules/aws/stages/network-hub/variables.tf` (new variable), `envs/aws/network/variables.tf`, `envs/aws/network/main.tf`

- [ ] **Step 1: Write the failing tests.** Append to `modules/aws/network/route53-resolver/tests/plan_assertions.tftest.hcl`:

```hcl
run "profile_carries_dns_settings_not_a_vpc" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive"
    profile_hosted_zone_arns  = { ssm = "arn:aws:route53:::hostedzone/Z0000000000000000001" }
  }

  assert {
    condition     = length(aws_route53profiles_resource_association.firewall) == 1 && jsondecode(aws_route53profiles_resource_association.firewall[0].resource_properties).priority == 101
    error_message = "The DNS Firewall rule group must ride the profile (with a priority) so every spoke that associates the profile is filtered."
  }

  assert {
    condition     = aws_route53profiles_resource_association.hosted_zones["ssm"].resource_arn == "arn:aws:route53:::hostedzone/Z0000000000000000001"
    error_message = "Each shared private hosted zone must be a profile resource."
  }

  assert {
    condition     = !anytrue([for r in values(aws_route53profiles_resource_association.hosted_zones) : strcontains(r.resource_arn, ":vpc/")])
    error_message = "A VPC is not a valid profile resource; VPCs join a profile through aws_route53profiles_association."
  }
}

run "resolver_endpoints_are_opt_in" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive"
  }

  assert {
    condition     = length(aws_route53_resolver_endpoint.inbound) == 0 && length(aws_route53_resolver_endpoint.outbound) == 0 && length(aws_security_group.resolver) == 0
    error_message = "Resolver endpoints (about USD 365 per month) must not exist unless enabled (ARC-21)."
  }
}

run "enabled_endpoints_get_a_dns_security_group" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive"
    enable_resolver_endpoints = true
    subnet_ids                = ["subnet-0a", "subnet-0b"]
    allowed_cidrs             = ["10.64.0.0/10", "192.168.0.0/16"]
  }

  assert {
    condition = (
      length(aws_route53_resolver_endpoint.inbound) == 1 &&
      length(aws_security_group.resolver) == 1 &&
      alltrue([for r in aws_security_group.resolver[0].ingress : r.from_port == 53 && r.to_port == 53 && toset(r.cidr_blocks) == toset(["10.64.0.0/10", "192.168.0.0/16"])]) &&
      length(aws_security_group.resolver[0].ingress) == 2
    )
    error_message = "Enabled endpoints need a module-owned security group that admits DNS (TCP and UDP 53) from allowed_cidrs only."
  }
}
```

Append to `.../variables_validation.tftest.hcl`:

```hcl
run "forward_rules_need_endpoints" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    org_arn       = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    query_log_destination_arn = "arn:aws:s3:::example-log-archive"
    forward_rules = { corp = { domain_name = "corp.example.", target_ips = ["192.168.0.10"] } }
  }

  expect_failures = [var.forward_rules]
}
```

- [ ] **Step 2: Run.** `make test TEST_DIRS=modules/aws/network/route53-resolver TERRAFORM=$TF`. Expected: undeclared `aws_route53profiles_resource_association.firewall`, `aws_security_group.resolver`, `var.enable_resolver_endpoints`.

- [ ] **Step 3: Implement.** Variables (replace lines 22-42 and add after `forward_rules`):

```hcl
variable "enable_resolver_endpoints" {
  description = "Create the inbound and outbound Resolver endpoints (2 ENIs each, about USD 365 per month together). Needed for on-premises resolution in either direction and for forward_rules. Default false."
  type        = bool
  default     = false
  nullable    = false
}

variable "subnet_ids" {
  description = "Subnet IDs (one per AZ, at least two) for the endpoint IPs. Required when enable_resolver_endpoints is true."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_resolver_endpoints || length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets when enable_resolver_endpoints is true."
  }
}

variable "security_group_ids" {
  description = "Security groups for the endpoints. Empty (default) = a module-owned group that admits DNS from allowed_cidrs."
  type        = list(string)
  default     = []
}

variable "allowed_cidrs" {
  description = "CIDRs that may send DNS (TCP/UDP 53) to the inbound endpoint when the module owns the security group (e.g. the org supernet and on-premises ranges)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.allowed_cidrs : can(cidrnetmask(c))])
    error_message = "allowed_cidrs entries must be IPv4 CIDR blocks."
  }
}

variable "profile_hosted_zone_arns" {
  description = "Private hosted zones to add to the Route 53 Profile, keyed by a plan-known name. Every VPC that associates the profile resolves them."
  type        = map(string)
  default     = {}
  nullable    = false
}
```

Add a second validation inside `forward_rules`:

```hcl
  validation {
    condition     = length(var.forward_rules) == 0 || var.enable_resolver_endpoints
    error_message = "forward_rules need the outbound endpoint: set enable_resolver_endpoints = true."
  }
```

`main.tf`: add `count = var.enable_resolver_endpoints ? 1 : 0` to both endpoints, set `security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.resolver[0].id]`, set `resolver_endpoint_id = aws_route53_resolver_endpoint.outbound[0].id` on the rules, and add:

```hcl
moved {
  from = aws_route53_resolver_endpoint.inbound
  to   = aws_route53_resolver_endpoint.inbound[0]
}

moved {
  from = aws_route53_resolver_endpoint.outbound
  to   = aws_route53_resolver_endpoint.outbound[0]
}

resource "aws_security_group" "resolver" {
  count = var.enable_resolver_endpoints && length(var.security_group_ids) == 0 ? 1 : 0

  name_prefix = "${var.name_prefix}-resolver-"
  description = "Route 53 Resolver endpoints: DNS from allowed_cidrs, DNS out to forward targets."
  vpc_id      = var.vpc_id

  ingress {
    description = "DNS over UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = var.allowed_cidrs
  }

  ingress {
    description = "DNS over TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  egress {
    description = "DNS over UDP to forward targets"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-egress-sgr - forward targets are caller-defined resolver IPs
  }

  egress {
    description = "DNS over TCP to forward targets"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-egress-sgr - forward targets are caller-defined resolver IPs
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-resolver" })

  lifecycle {
    create_before_destroy = true
  }
}
```

Replace `aws_route53profiles_resource_association.vpc` and the two data sources `aws_region` / `aws_caller_identity` (lines 84-92). `local.partition` (`partition.tf`) was only used by that association: delete `partition.tf` as well if `grep -n local.partition modules/aws/network/route53-resolver/*.tf` finds no other use with:

```hcl
# Profile resources: what every VPC that associates the profile inherits. A VPC
# is not a profile resource (ARC-6); VPCs join with aws_route53profiles_association.
resource "aws_route53profiles_resource_association" "firewall" {
  count = var.enable_dns_firewall ? 1 : 0

  name                = "${var.name_prefix}-profile-dns-firewall"
  profile_id          = aws_route53profiles_profile.this.id
  resource_arn        = aws_route53_resolver_firewall_rule_group.this[0].arn
  resource_properties = jsonencode({ priority = 101 })
}

resource "aws_route53profiles_resource_association" "rules" {
  for_each = var.forward_rules

  name         = "${var.name_prefix}-profile-rule-${each.key}"
  profile_id   = aws_route53profiles_profile.this.id
  resource_arn = aws_route53_resolver_rule.fwd[each.key].arn
}

resource "aws_route53profiles_resource_association" "hosted_zones" {
  for_each = var.profile_hosted_zone_arns

  name         = "${var.name_prefix}-profile-phz-${each.key}"
  profile_id   = aws_route53profiles_profile.this.id
  resource_arn = each.value
}
```

If an estate holds `aws_route53profiles_resource_association.vpc` in state, Terraform plans its delete; the association call was rejected by the API, so state is normally empty. Outputs: `value = try(aws_route53_resolver_endpoint.inbound[0].id, null)` (and outbound), descriptions add ", or null when enable_resolver_endpoints is false". Add output `inbound_endpoint_ips = try([for ip in aws_route53_resolver_endpoint.inbound[0].ip_address : ip.ip], [])`.

Stage `modules/aws/stages/network-hub/variables.tf`:

```hcl
variable "enable_resolver_endpoints" {
  description = "Create the Route 53 Resolver inbound/outbound endpoints in the egress VPC (about USD 365 per month). Null (default) = on only when enable_vpn is true, since only on-premises resolution needs them."
  type        = bool
  default     = null
}
```

Stage `main.tf:446-456`:

```hcl
module "route53_resolver" {
  source = "../../network/route53-resolver"

  vpc_id                    = module.egress_vpc.vpc_id
  subnet_ids                = module.egress_vpc.subnet_ids_by_tier["private"]
  org_arn                   = var.org_arn
  query_log_destination_arn = var.flow_log_destination_arn
  enable_dns_firewall       = true
  enable_resolver_endpoints = coalesce(var.enable_resolver_endpoints, var.enable_vpn)
  allowed_cidrs             = distinct(concat([var.top_cidr], var.vpn.onprem_cidrs))

  tags = var.tags
}
```

Root: add `variable "enable_resolver_endpoints" { type = bool, default = null, description = "Passed to the aws-network-hub stage. Null = on only with the VPN." }` to `envs/aws/network/variables.tf` and `enable_resolver_endpoints = var.enable_resolver_endpoints` to `module "aws_network_hub"`.

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/aws/network/route53-resolver modules/aws/stages/network-hub envs/aws/network" TERRAFORM=$TF`. Expected: pass.

- [ ] **Step 5: Docs.** `make docs`. UPGRADING entry under `### AWS`: "Resolver endpoints are now off unless the VPN is on (`enable_resolver_endpoints`). They could not be created before (placeholder security group), so no live resource is removed. The profile no longer lists the egress VPC as a resource." Update `docs/architecture/aws-landing-zone.md` DNS paragraph and the idle-cost line for `starter`. CHANGELOG bullet.

- [ ] **Step 6: Commit.** `git commit -m "fix(aws-network)!: make the Route 53 profile valid and resolver endpoints opt-in"`

---

### Task 8: Centralized interface endpoints serve the spokes (ARC-6)

**Files:**
- Modify: `modules/aws/network/vpc-endpoints/main.tf:15-62`, `variables.tf:28-32` (add new variables), `outputs.tf`
- Modify: `modules/aws/network/vpc-endpoints/tests/plan_assertions.tftest.hcl`
- Modify: `modules/aws/stages/network-hub/main.tf:430-456`
- Modify: every `override_module { target = module.vpc_endpoints ... }` in `modules/aws/stages/network-hub/tests/*.tftest.hcl` (add the new output)
- Modify: `docs/known-gaps.md` (D5)

- [ ] **Step 1: Write the failing test.** Append to `modules/aws/network/vpc-endpoints/tests/plan_assertions.tftest.hcl`:

```hcl
run "shared_private_dns_serves_other_vpcs" {
  command = plan

  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    region                    = "eu-west-2"
    org_id                    = "o-abc1234567"
    subnet_ids                = ["subnet-0a", "subnet-0b"]
    interface_services        = ["ssm", "sts"]
    allowed_cidrs             = ["10.64.0.0/10"]
    enable_shared_private_dns = true
  }

  assert {
    condition     = alltrue([for e in aws_vpc_endpoint.interface : !e.private_dns_enabled])
    error_message = "Shared endpoints must not use the hidden per-VPC private DNS zone; their names come from shareable private hosted zones."
  }

  assert {
    condition     = aws_route53_zone.endpoint["ssm"].name == "ssm.eu-west-2.amazonaws.com" && aws_route53_record.endpoint["sts"].name == "sts.eu-west-2.amazonaws.com" && aws_route53_record.endpoint["sts"].type == "A"
    error_message = "Each service needs a private hosted zone for its regional name with an alias A record to the endpoint."
  }

  assert {
    condition     = length(aws_security_group.endpoints) == 1 && alltrue([for r in aws_security_group.endpoints[0].ingress : r.from_port == 443 && r.to_port == 443 && r.cidr_blocks == ["10.64.0.0/10"]])
    error_message = "The endpoints need a security group that admits HTTPS from allowed_cidrs; the VPC default group denies everything."
  }

  assert {
    condition     = toset(keys(output.shared_dns_zone_arns)) == toset(["ssm", "sts"])
    error_message = "The zone ARNs must be exported keyed by service, for the Route 53 Profile."
  }
}
```

- [ ] **Step 2: Run.** `make test TEST_DIRS=modules/aws/network/vpc-endpoints TERRAFORM=$TF`. Expected: undeclared `var.enable_shared_private_dns`.

- [ ] **Step 3: Implement.** Add variables:

```hcl
variable "allowed_cidrs" {
  description = "CIDRs that may reach the interface endpoints on 443 when security_group_ids is empty (the module then owns the group). Use the org supernet for centralized endpoints."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.allowed_cidrs : can(cidrnetmask(c))])
    error_message = "allowed_cidrs entries must be IPv4 CIDR blocks."
  }
}

variable "enable_shared_private_dns" {
  description = "Serve each endpoint's regional name (<service>.<region>.amazonaws.com) from a private hosted zone with an alias record, instead of the endpoint's own private DNS, so other VPCs (through a Route 53 Profile) resolve the central endpoint. Only for services whose private DNS name is <service>.<region>.amazonaws.com. Default false."
  type        = bool
  default     = false
  nullable    = false
}
```

`main.tf`, in `aws_vpc_endpoint.interface`: `private_dns_enabled = !var.enable_shared_private_dns` and `security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : aws_security_group.endpoints[*].id`. Add:

```hcl
resource "aws_security_group" "endpoints" {
  count = length(var.security_group_ids) == 0 && length(var.allowed_cidrs) > 0 ? 1 : 0

  name_prefix = "interface-endpoints-"
  description = "Centralized interface endpoints: HTTPS from allowed_cidrs."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS to the interface endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  tags = merge(var.tags, { Name = "interface-endpoints" })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  shared_dns_services = var.enable_shared_private_dns ? toset(var.interface_services) : toset([])
}

# One zone per service, created after the endpoint stops using its own private
# DNS (a zone with the same name conflicts while private_dns_enabled is true).
resource "aws_route53_zone" "endpoint" {
  for_each = local.shared_dns_services

  name    = "${each.key}.${var.region}.amazonaws.com"
  comment = "Central interface endpoint for ${each.key} (shared through the Route 53 Profile)."

  vpc {
    vpc_id = var.vpc_id
  }

  tags = var.tags

  depends_on = [aws_vpc_endpoint.interface]
}

resource "aws_route53_record" "endpoint" {
  for_each = local.shared_dns_services

  zone_id = aws_route53_zone.endpoint[each.key].zone_id
  name    = "${each.key}.${var.region}.amazonaws.com"
  type    = "A"

  # The real provider always returns at least one dns_entry for an interface
  # endpoint; try() only keeps mock plans (empty computed lists) evaluable.
  alias {
    name                   = try(aws_vpc_endpoint.interface[each.key].dns_entry[0].dns_name, "")
    zone_id                = try(aws_vpc_endpoint.interface[each.key].dns_entry[0].hosted_zone_id, "")
    evaluate_target_health = false
  }
}
```

`outputs.tf`:

```hcl
output "shared_dns_zone_arns" {
  description = "Map of interface service to the ARN of its private hosted zone (enable_shared_private_dns). Add these to a Route 53 Profile so spoke VPCs resolve the central endpoints."
  value       = { for svc, z in aws_route53_zone.endpoint : svc => z.arn }
}
```

Stage `main.tf:430-456`: add to `module "vpc_endpoints"` `allowed_cidrs = [var.top_cidr]` and `enable_shared_private_dns = true`; add to `module "route53_resolver"` `profile_hosted_zone_arns = module.vpc_endpoints.shared_dns_zone_arns`. Because the keys of that map come from `var.interface_services` (plan-known), the `for_each` in Task 7 stays plan-safe. Add `shared_dns_zone_arns = { ssm = "arn:aws:route53:::hostedzone/Z0000000000000000001" }` to every `override_module { target = module.vpc_endpoints ... }` in the network-hub tests.

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/aws/network/vpc-endpoints modules/aws/stages/network-hub envs/aws/network" TERRAFORM=$TF`. Expected: pass.

- [ ] **Step 5: Docs.** `make docs`. Add to `docs/known-gaps.md` `## OPEN` a **DECISION** bullet: "Spoke traffic to the central interface endpoints crosses Network Firewall (per-GB processing). A direct TGW route would make return traffic asymmetric, which the stateful firewall drops. Revisit with a dedicated endpoints segment." UPGRADING entry: "Interface endpoints switch to shared private DNS. During the apply, the egress VPC resolves AWS service names through the new zones; the private DNS switch and the zone creation run in that order." CHANGELOG bullet.

- [ ] **Step 6: Commit.** `git commit -m "fix(aws-network)!: make the central interface endpoints reachable and resolvable from spokes"`

---

### Task 9: Spoke VPCs associate the shared Route 53 Profile (ARC-6)

**Files:**
- Modify: `modules/aws/stages/workload/main.tf:136-160` (after the TGW attachment), `modules/aws/stages/workload/variables.tf` (new variable after `tgw_id`)
- Modify: `modules/aws/stages/workload/tests/spoke_routing.tftest.hcl` (new run)
- Modify: `envs/aws/workload/variables.tf:53-65` (`network_contract`), `envs/aws/workload/main.tf:76-120`, `envs/aws/workload/config.tf:47-50`
- Modify: `config/landing-zone.schema.json` (`aws.contracts.network.properties`)

- [ ] **Step 1: Write the failing test.** Append to `modules/aws/stages/workload/tests/spoke_routing.tftest.hcl`:

```hcl
run "spoke_associates_the_dns_profile" {
  command = plan

  variables {
    environment         = "dev"
    resolver_profile_id = "rp-0123456789abcdef"
  }

  assert {
    condition     = length(aws_route53profiles_association.spoke) == 1 && aws_route53profiles_association.spoke[0].profile_id == "rp-0123456789abcdef" && aws_route53profiles_association.spoke[0].name == "workload-dev-dns-profile"
    error_message = "A hub-attached spoke must associate the org Route 53 Profile, so it gets DNS Firewall, forward rules and the endpoint zones."
  }
}

run "no_profile_no_association" {
  command = plan

  variables {
    environment = "dev"
  }

  assert {
    condition     = length(aws_route53profiles_association.spoke) == 0
    error_message = "Without a profile ID (standalone or an older network contract) nothing is associated."
  }
}
```

- [ ] **Step 2: Run.** `make test TEST_DIRS=modules/aws/stages/workload TERRAFORM=$TF`. Expected: undeclared `var.resolver_profile_id`.

- [ ] **Step 3: Implement.** Stage variable:

```hcl
variable "resolver_profile_id" {
  description = "ID of the org Route 53 Profile shared by aws-network over RAM (network contract resolver_profile_id). The spoke VPC associates it and inherits DNS Firewall, resolver forward rules and the central endpoint zones. Null (default) = no association."
  type        = string
  default     = null
}
```

Stage resource:

```hcl
resource "aws_route53profiles_association" "spoke" {
  count = var.resolver_profile_id == null ? 0 : 1

  name        = "${local.name}-dns-profile"
  profile_id  = var.resolver_profile_id
  resource_id = module.vpc.vpc_id

  tags = var.tags
}
```

Root: extend `network_contract` type with `resolver_profile_id = optional(string)`; in `config.tf` `network_contract` add `resolver_profile_id = try(tostring(local.lz.aws.contracts.network.resolver_profile_id), null)`; in `main.tf` add:

```hcl
  resolver_profile_id = (
    !var.enable_network_hub ? null :
    local.read_network ? try(local.network_remote.resolver_profile_id, null) : local.network_contract.resolver_profile_id
  )
```

and pass `resolver_profile_id = local.resolver_profile_id` to `module "aws_workload"`. Schema: add `"resolver_profile_id": {"type": "string", "pattern": "^rp-[0-9a-z]+$"}` to `aws.contracts.network.properties`.

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/aws/stages/workload envs/aws/workload" TERRAFORM=$TF`, `make consistency config-check`. Expected: pass.

- [ ] **Step 5: Docs.** `make docs`. CHANGELOG bullet. `docs/architecture/aws-landing-zone.md`: "Each hub-attached spoke associates the org Route 53 Profile." No UPGRADING entry (additive).

- [ ] **Step 6: Commit.** `git commit -m "feat(aws-workload): associate the org Route 53 Profile with each spoke VPC"`

---

### Task 10: Starter spokes egress through NAT without the firewall (ARC-10, D4)

**Files:**
- Modify: `modules/aws/stages/network-hub/main.tf:45-75` (routing locals), `modules/aws/stages/network-hub/spokes.tf:51-58`
- Modify: `modules/aws/stages/network-hub/variables.tf:293-296` (remove the firewall-only validation), add a `terraform_data` guard in `main.tf` near line 409
- Modify: `modules/aws/stages/network-hub/tests/spoke_routing.tftest.hcl` (new run)

- [ ] **Step 1: Write the failing test.** Append to `modules/aws/stages/network-hub/tests/spoke_routing.tftest.hcl`:

```hcl
run "starter_spokes_egress_through_nat" {
  command = apply

  variables {
    enable_network_firewall = false
    spoke_attachments = {
      dev = { attachment_id = "tgw-attach-0fedcba9876543210", segment = "nonprod" }
    }
  }

  assert {
    condition     = output.tgw_inspection_routes["nonprod:default"].attachment == "egress" && output.tgw_inspection_routes["prod:default"].attachment == "egress"
    error_message = "Without the firewall the segment defaults must go to the egress attachment, or spokes have no egress (ARC-10)."
  }

  assert {
    condition     = aws_ec2_transit_gateway_route_table_propagation.spoke["dev"].transit_gateway_route_table_id == "tgw-rtb-shared000000"
    error_message = "NAT replies leave the egress VPC through the shared table, so the spoke must propagate there."
  }

  assert {
    condition     = !contains(keys(output.tgw_inspection_routes), "shared:spokes") && !contains(keys(output.tgw_inspection_routes), "inspection:default")
    error_message = "No route may point at the inspection attachment when there is no firewall to forward it."
  }
}

run "starter_with_vpn_is_rejected" {
  command = plan

  variables {
    enable_network_firewall = false
    enable_vpn              = true
    vpn                     = { customer_gateway_ip = "203.0.113.10" }
  }

  expect_failures = [terraform_data.hybrid_needs_inspection]
}
```

- [ ] **Step 2: Run.** `make test TEST_DIRS=modules/aws/stages/network-hub TERRAFORM=$TF`. Expected: the first run fails on the variable validation "spoke_attachments ... needs enable_network_firewall = true"; the second fails on the undeclared guard.

- [ ] **Step 3: Implement.** In `main.tf` replace lines 56-74 with:

```hcl
  # Spoke segments default-route to inspection when the firewall exists, else
  # straight to the egress attachment (starter: NAT egress, not inspected; D4).
  spoke_default_attachment = var.enable_network_firewall ? "inspection" : "egress"

  tgw_routes = merge(
    {
      "prod:default"    = { route_table = "prod", cidr = "0.0.0.0/0", attachment = local.spoke_default_attachment }
      "nonprod:default" = { route_table = "nonprod", cidr = "0.0.0.0/0", attachment = local.spoke_default_attachment }
    },
    # On-premises traffic is default-routed to inspection (hybrid table).
    var.enable_vpn ? { "hybrid:default" = { route_table = "hybrid", cidr = "0.0.0.0/0", attachment = "inspection" } } : {},
    local.spoke_hub_routes,
  )

  # Hub routes the inspected spokes need (spokes.tf); only with a firewall and
  # at least one spoke, so an estate without spokes plans no change.
  spoke_hub_routes = length(var.spoke_attachments) > 0 && var.enable_network_firewall ? {
    "inspection:default" = { route_table = "inspection", cidr = "0.0.0.0/0", attachment = "egress" }
    "shared:spokes"      = { route_table = "shared", cidr = var.top_cidr, attachment = "inspection" }
  } : {}

  # Where spoke CIDRs propagate: the inspection table (inspected path), or the
  # shared table that the egress attachment uses for NAT replies (starter).
  spoke_return_route_table = var.enable_network_firewall ? "inspection" : "shared"
```

In `spokes.tf:55` use `transit_gateway_route_table_id = module.transit_gateway.route_table_ids[local.spoke_return_route_table]`. Delete the validation at `variables.tf:293-296` and update the `spoke_attachments` description sentence about the inspection table: "...propagated into the inspection route table (or, without the firewall, the shared route table)". Add after `terraform_data.production_egress_enforced`:

```hcl
# The hybrid table sends on-premises traffic to inspection, which forwards
# nothing without the firewall. Starter estates cannot run the VPN.
resource "terraform_data" "hybrid_needs_inspection" {
  input = var.enable_vpn

  lifecycle {
    precondition {
      condition     = !var.enable_vpn || var.enable_network_firewall
      error_message = "enable_vpn needs enable_network_firewall = true (profile production): on-premises traffic is routed through the inspection VPC, which forwards nothing without the firewall."
    }
  }
}
```

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/aws/stages/network-hub envs/aws/network" TERRAFORM=$TF`. Expected: pass; `spokes_are_accepted_associated_and_propagated` still asserts the inspection table because the firewall defaults to on.

- [ ] **Step 5: Docs.** `make docs`. In `config/landing-zone.example.yaml:381-388` change "propagated into the inspection table" to "propagated into the inspection table (starter: the shared table; egress is NAT only, not inspected)". Update `docs/architecture/aws-landing-zone.md` starter paragraph and the audit's cost note in `docs/guides/` cost page if it mentions starter spokes. UPGRADING entry under `### AWS`: "Starter estates may now list `aws.network.spoke_attachments`; their spokes egress through NAT without inspection. A starter estate with `aws.network.vpn.enabled: true` now fails the plan: that combination never forwarded traffic." CHANGELOG bullet.

- [ ] **Step 6: Commit.** `git commit -m "fix(aws-network)!: give starter spokes NAT egress and reject starter VPN"`

---

### Task 11: Prod and non-prod spokes cannot reach each other (ARC-11)

**Files:**
- Modify: `modules/aws/stages/network-hub/variables.tf:266-297` (`spoke_attachments`), `modules/aws/stages/network-hub/spokes.tf` (append)
- Modify: `modules/aws/stages/network-hub/outputs.tf` (new output)
- Modify: `envs/aws/network/config.tf:45-52,97-98`
- Modify: `modules/aws/stages/network-hub/tests/spoke_routing.tftest.hcl`, `envs/aws/network/tests/spoke_routing.tftest.hcl`
- Modify: `config/landing-zone.schema.json` (`aws.network.spoke_attachments.additionalProperties.properties`)

- [ ] **Step 1: Write the failing test.** Append to `modules/aws/stages/network-hub/tests/spoke_routing.tftest.hcl`:

```hcl
run "segments_blackhole_each_others_spokes" {
  command = apply

  variables {
    spoke_attachments = {
      prod = { attachment_id = "tgw-attach-0123456789abcdef0", segment = "prod", cidr = "10.73.0.0/16" }
      dev  = { attachment_id = "tgw-attach-0fedcba9876543210", segment = "nonprod", cidr = "10.72.0.0/16" }
    }
  }

  assert {
    condition = (
      aws_ec2_transit_gateway_route.segment_isolation["prod|dev"].blackhole &&
      aws_ec2_transit_gateway_route.segment_isolation["prod|dev"].transit_gateway_route_table_id == "tgw-rtb-prod00000000" &&
      aws_ec2_transit_gateway_route.segment_isolation["prod|dev"].destination_cidr_block == "10.72.0.0/16" &&
      aws_ec2_transit_gateway_route.segment_isolation["nonprod|prod"].transit_gateway_route_table_id == "tgw-rtb-nonprod00000" &&
      aws_ec2_transit_gateway_route.segment_isolation["nonprod|prod"].destination_cidr_block == "10.73.0.0/16" &&
      length(aws_ec2_transit_gateway_route.segment_isolation) == 2
    )
    error_message = "Each segment table must blackhole the other segment's spoke CIDRs, so prod and non-prod cannot reach each other through inspection or NAT (ARC-11)."
  }
}
```

Append to `envs/aws/network/tests/spoke_routing.tftest.hcl` a run that uses `tests/fixtures/landing-zone-spokes.yaml` and asserts `local.spoke_attachments["dev"].cidr == "10.72.0.0/16"`; add `vpc_cidr: 10.72.0.0/16` to the `dev` entry of `aws.workload_environments` in that fixture (add the entry with `account_key: workload_dev` if absent).

- [ ] **Step 2: Run.** `make test TEST_DIRS="modules/aws/stages/network-hub envs/aws/network" TERRAFORM=$TF`. Expected: the variable type rejects `cidr`; `segment_isolation` is undeclared.

- [ ] **Step 3: Implement.** In `spoke_attachments` add `cidr = optional(string)` to the object, a sentence to the description ("cidr is the spoke VPC CIDR; when set, the other segment's table blackholes it"), and:

```hcl
  validation {
    condition     = alltrue([for k, s in var.spoke_attachments : s.cidr == null || can(cidrnetmask(coalesce(s.cidr, "x")))])
    error_message = "spoke_attachments[*].cidr must be an IPv4 CIDR block (the spoke's vpc_cidr)."
  }
```

Append to `spokes.tf`:

```hcl
# Segment isolation (ARC-11). Both segments default-route to the same
# inspection (or egress) attachment, whose table knows every spoke, so prod
# could reach non-prod. A blackhole for each spoke CIDR in the OTHER segment's
# table wins by longest prefix and drops it at the TGW. Keyed
# "<table>|<spoke>": plan-known.
locals {
  segment_isolation_routes = merge([
    for k, s in var.spoke_attachments : {
      for seg in ["prod", "nonprod"] : "${seg}|${k}" => { route_table = seg, cidr = s.cidr }
      if seg != s.segment
    } if s.cidr != null
  ]...)
}

resource "aws_ec2_transit_gateway_route" "segment_isolation" {
  for_each = local.segment_isolation_routes

  destination_cidr_block         = each.value.cidr
  transit_gateway_route_table_id = module.transit_gateway.route_table_ids[each.value.route_table]
  blackhole                      = true
}

check "segments_isolated" {
  assert {
    condition = !(
      contains([for s in values(var.spoke_attachments) : s.segment], "prod") &&
      contains([for s in values(var.spoke_attachments) : s.segment], "nonprod")
    ) || alltrue([for s in values(var.spoke_attachments) : s.cidr != null])
    error_message = "prod and nonprod spokes are both attached but some spoke_attachments have no cidr, so their segments can reach each other. Set aws.workload_environments.<env>.vpc_cidr (the root copies it) or spoke_attachments.<key>.cidr."
  }
}
```

Add output `segment_isolation_routes = local.segment_isolation_routes` with description "Blackhole routes that isolate prod and non-prod spokes, keyed <table>|<spoke>.". In `envs/aws/network/config.tf` `cfg` add:

```hcl
    # aws.workload_environments.<env>.vpc_cidr, copied onto a spoke_attachments
    # entry with the same key that sets no cidr (segment isolation, ARC-11).
    workload_vpc_cidrs = { for env, e in try({ for k, v in local.lz.aws.workload_environments : k => v }, {}) : env => tostring(e.vpc_cidr) if try(e.vpc_cidr, null) != null }
```

and change the effective value at line 98:

```hcl
  spoke_attachments_input = jsondecode(var.spoke_attachments != null ? jsonencode(var.spoke_attachments) : coalesce(local.cfg.spoke_attachments, "{}"))
  # Every entry gets the same attribute set, so the map has one element type
  # (config entries may omit accept or cidr).
  spoke_attachments = {
    for k, s in local.spoke_attachments_input : k => {
      attachment_id = s.attachment_id
      segment       = s.segment
      accept        = try(s.accept, true)
      cidr          = try(s.cidr, null) != null ? s.cidr : lookup(local.cfg.workload_vpc_cidrs, k, null)
    }
  }
```

Add `cidr = optional(string)` to the root `spoke_attachments` variable type (`envs/aws/network/variables.tf:312-320`) and extend its description with "cidr (default aws.workload_environments.<key>.vpc_cidr) is blackholed in the other segment's table". Schema: add `"cidr": {"type": "string", "pattern": "^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$"}` to the `spoke_attachments` item properties.

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/aws/stages/network-hub envs/aws/network" TERRAFORM=$TF`, `make config-check`. Expected: pass.

- [ ] **Step 5: Docs.** `make docs`. `docs/architecture/aws-landing-zone.md` segmentation paragraph: replace "prod and nonprod never learn each other's routes directly" with the blackhole mechanism. CHANGELOG bullet. No UPGRADING entry: blackholes are added routes, and existing spokes keep running; note in the CHANGELOG that cross-segment flows that worked before now drop.

- [ ] **Step 6: Commit.** `git commit -m "fix(aws-network): blackhole cross-segment spoke routes on the transit gateway"`

---

### Task 12: IPAM capacity lever and pool share scope (ARC-4)

**Files:**
- Modify: `modules/aws/network/ipam/main.tf:55-81`, `variables.tf` (new variables), `tests/plan_assertions.tftest.hcl`
- Modify: `modules/aws/stages/network-hub/main.tf:81-90`, `variables.tf` (pass-through)
- Modify: `envs/aws/network/main.tf:49-81`, `envs/aws/network/config.tf`, `envs/aws/network/variables.tf`
- Modify: `config/landing-zone.schema.json`, `config/landing-zone.example.yaml:352-360`

- [ ] **Step 1: Write the failing test.** Append to `modules/aws/network/ipam/tests/plan_assertions.tftest.hcl`:

```hcl
run "regional_pool_can_grow_and_share_narrowly" {
  command = plan

  variables {
    org_arn                   = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    aws_enabled_regions       = ["eu-west-2"]
    top_cidr                  = "10.64.0.0/10"
    regional_cidrs            = { eu-west-2 = "10.64.0.0/12" }
    regional_additional_cidrs = { eu-west-2 = ["10.80.0.0/12"] }
    share_principal_arns      = ["arn:aws:organizations::111111111111:ou/o-abc1234567/ou-ab12-workload1"]
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr.regional_additional["eu-west-2|10.80.0.0/12"].cidr == "10.80.0.0/12"
    error_message = "A region must be able to provision a second CIDR when its first /12 is full (14 workloads at /16)."
  }

  assert {
    condition     = length(aws_ram_principal_association.org) == 0 && keys(aws_ram_principal_association.this) == ["arn:aws:organizations::111111111111:ou/o-abc1234567/ou-ab12-workload1"]
    error_message = "The pools must be shareable to named OUs only, so accounts outside them cannot drain the pool."
  }
}

run "default_share_stays_org_wide" {
  command = plan

  variables {
    org_arn = "arn:aws:organizations::111111111111:organization/o-abc1234567"
  }

  assert {
    condition     = length(aws_ram_principal_association.org) == 1 && aws_ram_principal_association.org[0].principal == "arn:aws:organizations::111111111111:organization/o-abc1234567" && length(aws_ram_principal_association.this) == 0
    error_message = "With no share_principal_arns the share keeps the org principal at aws_ram_principal_association.org[0] (moved from the un-indexed address)."
  }
}
```

- [ ] **Step 2: Run.** `make test TEST_DIRS=modules/aws/network/ipam TERRAFORM=$TF`. Expected: undeclared `regional_additional_cidrs`.

- [ ] **Step 3: Implement.** Variables:

```hcl
variable "regional_additional_cidrs" {
  description = "Extra CIDRs per region, provisioned into that region's pool next to regional_cidrs (capacity growth without touching existing allocations). Each must sit in top_cidr and overlap nothing."
  type        = map(list(string))
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue(flatten([for r, cs in var.regional_additional_cidrs : [for c in cs : can(cidrhost(c, 0)) && contains(var.aws_enabled_regions, r)]]))
    error_message = "regional_additional_cidrs keys must be enabled regions and values valid IPv4 CIDR blocks."
  }
}

variable "share_principal_arns" {
  description = "RAM principals the regional pools are shared with. Null (default) = the whole organization (org_arn). Use the Workloads OU ARN(s) so other accounts cannot allocate from the pools."
  type        = list(string)
  default     = null

  validation {
    condition     = var.share_principal_arns == null || alltrue([for p in (var.share_principal_arns == null ? [] : var.share_principal_arns) : can(regex("^arn:aws(-us-gov|-cn)?:organizations::[0-9]{12}:(organization|ou)/", p))])
    error_message = "share_principal_arns entries must be AWS Organizations organization or OU ARNs."
  }
}
```

`main.tf`: after `aws_vpc_ipam_pool_cidr.regional` add

```hcl
resource "aws_vpc_ipam_pool_cidr" "regional_additional" {
  for_each = merge([
    for r, cs in var.regional_additional_cidrs : { for c in cs : "${r}|${c}" => { region = r, cidr = c } }
  ]...)

  ipam_pool_id = aws_vpc_ipam_pool.regional[each.value.region].id
  cidr         = each.value.cidr

  depends_on = [aws_vpc_ipam_pool_cidr.top]
}
```

Replace `aws_ram_principal_association.org` (lines 78-81) with the block below. The org association keeps its address (a `moved` block cannot use a variable as a key), so an existing estate plans only an address move:

```hcl
resource "aws_ram_principal_association" "org" {
  count = var.share_principal_arns == null ? 1 : 0

  principal          = var.org_arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

resource "aws_ram_principal_association" "this" {
  for_each = toset(var.share_principal_arns == null ? [] : var.share_principal_arns)

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.this.arn
}

moved {
  from = aws_ram_principal_association.org
  to   = aws_ram_principal_association.org[0]
}
```

Stage: pass `regional_additional_cidrs` and `share_principal_arns` (new stage variables with the same types and defaults). Root `config.tf` `cfg`:

```hcl
    regional_additional_cidrs = try({ for r, cs in local.lz.aws.network.regional_additional_cidrs : r => [for c in cs : tostring(c)] }, null)
    ipam_share_ou_keys        = try([for k in local.lz.aws.network.ipam_share_ou_keys : tostring(k)], null)
```

Root locals: `ipam_share_principal_arns = local.cfg.ipam_share_ou_keys == null ? null : [for k in local.cfg.ipam_share_ou_keys : "arn:${local.partition}:organizations::${local.org.management_account_id}:ou/${local.org.organization_id}/${local.org.ou_ids[k]}"]`, plus a `terraform_data` precondition that every key exists in `local.org.ou_ids`. Schema for both keys under `aws.network` (`regional_additional_cidrs`: object of arrays of CIDR strings; `ipam_share_ou_keys`: array of strings). UPGRADING entry for anyone who sets `ipam_share_ou_keys`: "Every account that already allocates from the pool must be in a listed OU; otherwise RAM removes its access to the pool for new VPCs (existing VPCs keep their CIDR)."

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/aws/network/ipam modules/aws/stages/network-hub envs/aws/network" TERRAFORM=$TF`, `make config-check`. Expected: pass.

- [ ] **Step 5: Docs.** `make docs`. In `docs/runbooks/aws-cidr-expansion.md` add a section "Region pool is full: add `aws.network.regional_additional_cidrs`". CHANGELOG bullet.

- [ ] **Step 6: Commit.** `git commit -m "feat(aws-network): grow regional IPAM pools and share them with named OUs"`

---

### Task 13: Document capacity and the GKE secondary ranges in the IP plan (ARC-4)

**Files:**
- Modify: `docs/architecture/cidr-plan.md:23-58`
- Modify: `docs/architecture/network-topology.md:170-172`
- Modify: `docs/known-gaps.md`

- [ ] **Step 1: Write the failing check.** `grep -n "Capacity" docs/architecture/cidr-plan.md` returns nothing; `grep -n "100.64.0.0/10" docs/architecture/cidr-plan.md` returns nothing.

- [ ] **Step 2: Confirm.** Both greps exit 1.

- [ ] **Step 3: Implement.** Add to `cidr-plan.md` after `## AWS`:

```markdown
## Capacity

| Space | Unit | Fits | Growth path |
|---|---|---|---|
| GCP environments (`10.10.0.0/16` to `10.15.0.0/16`) | one `/16` per environment | 6 environments | Give new environments a `/18` from `10.2.0.0/15` (8 more), or use the Reserved buffer after updating this plan. |
| AWS regional pool (`10.64.0.0/12`) | one `/16` per VPC, minus inspection and egress | 14 workloads per region | `aws.network.regional_additional_cidrs` adds a second `/12` from `10.80.0.0/12` (Task 12). |

## GKE secondary ranges

GKE Pods and Services use non-RFC 1918 space, so they never consume the `/16` of an environment.

| Environment index (sorted key order) | Pods (`/14`) | Services (`/20`) |
|---|---|---|
| i | `cidrsubnet("100.64.0.0/10", 4, i)` | `cidrsubnet("100.127.0.0/16", 4, i)` |

Set them on the environment's private subnet through `secondary_ranges` (see
[cidr-expansion.md](../runbooks/cidr-expansion.md)), and name them in
`app_platform.gke.cluster_secondary_range_name` / `services_secondary_range_name`.
```

Replace `network-topology.md:172` ("allocated within the private subnet when `enable_gke = true`") with "come from `100.64.0.0/10` (Pods) and `100.127.0.0/16` (Services); see `[cidr-plan.md](cidr-plan.md#gke-secondary-ranges)`". Add an **OPEN** bullet to `docs/known-gaps.md`: "GKE secondary ranges are documented, not provisioned: an environment that enables GKE must set `secondary_ranges` by hand."

- [ ] **Step 4: Verify.** Both greps now match; `make links`.

- [ ] **Step 5: Docs.** CHANGELOG bullet.

- [ ] **Step 6: Commit.** `git commit -m "docs(network): state IP plan capacity and the GKE secondary range plan"`

---

### Task 14: Hub peering: one spoke name, an INACTIVE warning, a peering limit, the runbook step (ARC-5, D3)

**Files:**
- Modify: `envs/gcp/projects/outputs.tf:14-31` (contract) and `:54-65` (type)
- Modify: `envs/gcp/network-hub/data.tf:43-51`, `envs/gcp/network-hub/variables.tf:228-245`, `envs/gcp/network-hub/config.tf:81-92`
- Modify: `envs/gcp/workload/variables.tf:118-134`, `envs/gcp/workload/config.tf` (projects_contract block), `envs/gcp/workload/main.tf:117-133` (fallback) and module call, add a `check`
- Modify: `modules/gcp/stages/environment/variables.tf:104-125`, `modules/gcp/stages/environment/main.tf:50-51`
- Modify: `modules/gcp/stages/network-hub/main.tf:151-162`, `modules/gcp/stages/network-hub/variables.tf:315-329`
- Modify: `modules/gcp/stages/network-hub/tests/variables_validation.tftest.hcl`, `envs/gcp/network-hub/tests/spoke_peerings.tftest.hcl`
- Modify: `docs/runbooks/add-environment.md:95-117`

- [ ] **Step 1: Write the failing tests.** Append to `modules/gcp/stages/network-hub/tests/variables_validation.tftest.hcl` (reuse its file variables):

```hcl
run "hub_peerings_over_the_limit_rejected" {
  command = plan

  variables {
    hub_peering_limit = 2
    spoke_peerings = {
      dev  = { network_self_link = "projects/p-dev/global/networks/mock-dev-vpc" }
      uat  = { network_self_link = "projects/p-uat/global/networks/mock-uat-vpc" }
      prod = { network_self_link = "projects/p-prod/global/networks/mock-prod-vpc" }
    }
  }

  expect_failures = [terraform_data.hub_peering_limit]
}
```

Append to `envs/gcp/network-hub/tests/spoke_peerings.tftest.hcl`:

```hcl
run "spoke_network_name_comes_from_the_projects_contract" {
  command = plan

  variables {
    projects_contract = {
      project_ids     = { shared-hub = "p-hub", shared-dns = "p-dns", dev-host = "p-dev" }
      project_numbers = { shared-hub = "1", shared-dns = "2", dev-host = "3" }
      environment_config = {
        dev = {
          folder_id = "folders/1", host_project_id = "p-dev", host_project_number = "3"
          region = "europe-west2", cidr_block = "10.10.0.0/16", spoke_network_name = "custom-dev-vpc"
        }
      }
    }
  }

  assert {
    condition     = local.spoke_peering_candidates["dev"].network_name == "custom-dev-vpc"
    error_message = "gcp-network-hub must peer with the network name gcp-projects publishes, not a second derivation (ARC-5)."
  }
}
```

(Keep the file's existing `override_data` for `data.google_compute_networks.spoke`; add `environments = { dev = {...} }` if the file does not already define `dev`.)

- [ ] **Step 2: Run.** `make test TEST_DIRS="modules/gcp/stages/network-hub envs/gcp/network-hub" TERRAFORM=$TF`. Expected: undeclared `hub_peering_limit`; `spoke_network_name` not in the variable type.

- [ ] **Step 3: Implement.**

`envs/gcp/projects/outputs.tf` contract `environment_config`, add `spoke_network_name = "${local.project_prefix}-${env_key}-vpc"`, and `spoke_network_name = string` to the output type. In both `envs/gcp/network-hub/variables.tf` and `envs/gcp/workload/variables.tf` add `spoke_network_name = optional(string)` to the `environment_config` object of `projects_contract` (byte-identical in both, `scripts/check-contracts.sh` step 3), and in both `config.tf` files add `spoke_network_name = try(tostring(e.spoke_network_name), null)` to the config-file `environment_config`.

`envs/gcp/network-hub/data.tf:46`:

```hcl
      network_name = coalesce(try(local.projects.environment_config[env].spoke_network_name, null), "${local.project_prefix}-${env}-vpc")
```

`modules/gcp/stages/environment/variables.tf` `network` object: add `name = optional(string)` with the description sentence "name: the spoke VPC name (default <project_prefix>-<environment>-vpc; gcp-workload passes the gcp-projects contract value)". `modules/gcp/stages/environment/main.tf:51`:

```hcl
    name            = coalesce(var.network.name, "${var.project_prefix}-${var.environment}-vpc")
```

`envs/gcp/workload/main.tf`: in the `env_config` fallback add `spoke_network_name = null`; in `module "environment"` set the network name: `network = merge(<current network value>, { name = try(local.env_config.spoke_network_name, null) })` (read the current argument first and wrap it). Add:

```hcl
# The hub side (hub-to-<env>) is created by gcp-network-hub only once this
# network exists, so the first apply leaves the spoke side INACTIVE (ARC-5).
check "hub_peering_active" {
  assert {
    condition     = local.hub_network == null || local.network_connectivity != "peering" || try(module.environment.vpc_peerings["hub-peering"].peering_state, "ACTIVE") != "INACTIVE"
    error_message = "The hub peering of ${var.environment} is INACTIVE: queue a run of gcp-network-hub (docs/runbooks/add-environment.md step 5), then re-plan this workspace."
  }
}
```

`modules/gcp/stages/network-hub/variables.tf`:

```hcl
variable "hub_peering_limit" {
  description = "Most environment peerings the hub VPC may carry. The default quota is 25 peerings per network; one is kept for the hub's own Private Service Access peering. Raise it only after the quota is raised."
  type        = number
  default     = 24
  nullable    = false

  validation {
    condition     = var.hub_peering_limit >= 1
    error_message = "hub_peering_limit must be at least 1."
  }
}
```

`modules/gcp/stages/network-hub/main.tf`, before `google_compute_network_peering.hub_to_spoke`:

```hcl
resource "terraform_data" "hub_peering_limit" {
  input = length(var.spoke_peerings)

  lifecycle {
    precondition {
      condition     = length(var.spoke_peerings) <= var.hub_peering_limit
      error_message = "${length(var.spoke_peerings)} environment peerings exceed hub_peering_limit (${var.hub_peering_limit}). Move environments to NCC (gcp.network.connectivity: ncc, docs/runbooks/gcp-peering-to-ncc-migration.md) or raise the peering quota first."
    }
  }
}
```

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/gcp/stages/network-hub modules/gcp/stages/environment envs/gcp/network-hub envs/gcp/workload envs/gcp/projects" TERRAFORM=$TF`, `make consistency`. Expected: pass.

- [ ] **Step 5: Docs.** `make docs`. In `docs/runbooks/add-environment.md` after the step-4 section (line 117) add `### 5. Run gcp-network-hub again to peer the hub side`: "The hub side of the peering (`hub-to-<env>`) can only be created once `gcp-workload-<env>` has created the spoke network. Queue a run of `gcp-network-hub` and apply it. Then re-plan `gcp-workload-<env>`: its `hub_peering_state` output reads `ACTIVE` and the `hub_peering_active` check passes. Skip this step for `connectivity: ncc`." Renumber the later steps. Add the row `| 5 | gcp-network-hub (second run) | The hub-side peering hub-to-<env> |` to the table at lines 95-101. CHANGELOG bullet. No UPGRADING entry (optional contract field, fallback kept).

- [ ] **Step 6: Commit.** `git commit -m "fix(gcp-network): single spoke network name, peering limit and INACTIVE warning"`

---

### Task 15: GCP hybrid: advertise the spokes and forward DNS (ARC-12)

**Files:**
- Modify: `modules/gcp/stages/network-hub/main.tf:83-125` (module.hub vpn and interconnects), add DNS policy and forwarding zones after `module "dns_anchor"`
- Modify: `modules/gcp/stages/network-hub/variables.tf` (new variables `hybrid_advertised_ranges`, `hybrid_dns`)
- Modify: `modules/gcp/stages/network-hub/tests/hybrid.tftest.hcl`
- Modify: `envs/gcp/network-hub/main.tf:54-58`, `envs/gcp/network-hub/variables.tf`, `envs/gcp/network-hub/config.tf:41-47,112-114`
- Modify: `config/landing-zone.schema.json` (`gcp.network.hybrid_dns`), `config/landing-zone.example.yaml` (gcp.network)

- [ ] **Step 1: Write the failing test.** Append to `modules/gcp/stages/network-hub/tests/hybrid.tftest.hcl` (reuse its overrides; it already enables the VPN in some runs: copy that run's `vpn` value):

```hcl
run "vpn_advertises_hub_and_environment_ranges_by_default" {
  command = plan

  variables {
    vpn = {
      enabled          = true
      peer_gateway_ips = ["203.0.113.1", "203.0.113.2"]
    }
    hybrid_advertised_ranges = [{ range = "10.10.0.0/16", description = "environment dev" }]
  }

  assert {
    condition     = local.vpn_effective.advertised_ip_ranges == [{ range = "10.0.0.0/16", description = "hub VPC" }, { range = "10.10.0.0/16", description = "environment dev" }]
    error_message = "DEFAULT BGP mode advertises only the hub subnets; peered spokes are never announced on-premises. The hub CIDR and every environment CIDR must be advertised (ARC-12)."
  }

  assert {
    condition     = length(google_dns_policy.hub_inbound) == 1 && google_dns_policy.hub_inbound[0].enable_inbound_forwarding && google_dns_policy.hub_inbound[0].networks[0].network_url == "projects/mock-hub-project/global/networks/hub-vpc-core"
    error_message = "On-premises resolvers need an inbound forwarding address in the hub VPC."
  }
}

run "explicit_advertised_ranges_win" {
  command = plan

  variables {
    vpn = {
      enabled              = true
      peer_gateway_ips     = ["203.0.113.1", "203.0.113.2"]
      advertised_ip_ranges = [{ range = "10.0.0.0/12", description = "GCP block" }]
    }
    hybrid_advertised_ranges = [{ range = "10.10.0.0/16", description = "environment dev" }]
  }

  assert {
    condition     = local.vpn_effective.advertised_ip_ranges == [{ range = "10.0.0.0/12", description = "GCP block" }]
    error_message = "Explicit vpn.advertised_ip_ranges must win over the derived list."
  }
}

run "on_prem_zones_are_forwarded" {
  command = plan

  variables {
    vpn = {
      enabled          = true
      peer_gateway_ips = ["203.0.113.1", "203.0.113.2"]
    }
    hybrid_dns = {
      forward_zones = { corp = { dns_name = "corp.example.com.", target_ips = ["192.168.0.10", "192.168.0.11"] } }
    }
  }

  assert {
    condition     = module.hybrid_forward_zones["corp"].zone.dns_name == "corp.example.com." && length(module.hybrid_forward_zones["corp"].zone.forwarding_config[0].target_name_servers) == 2
    error_message = "On-premises domains must be forwarded to the on-premises resolvers from the hub."
  }
}

run "no_hybrid_no_dns_policy" {
  command = plan

  assert {
    condition     = length(google_dns_policy.hub_inbound) == 0 && length(module.hybrid_forward_zones) == 0
    error_message = "Without VPN or Interconnect nothing hybrid is created."
  }
}
```

If the `network/dns` module output is not named `zone`, use the output that exposes the managed zone (the plan_assertions suite reads `module.dns_anchor.dns_zones[...].zone`, so `zone` exists).

- [ ] **Step 2: Run.** `make test TEST_DIRS=modules/gcp/stages/network-hub TERRAFORM=$TF`. Expected: undeclared `hybrid_advertised_ranges`, `local.vpn_effective`, `google_dns_policy.hub_inbound`.

- [ ] **Step 3: Implement.** Variables:

```hcl
variable "hybrid_advertised_ranges" {
  description = "Extra prefixes the hub Cloud Router announces over VPN/Interconnect when vpn.advertised_ip_ranges (or an interconnect's) is empty: normally every environment CIDR (envs/gcp/network-hub derives them). The hub CIDR is always included. Peered spoke subnets are never advertised by DEFAULT mode."
  type = list(object({
    range       = string
    description = string
  }))
  default  = []
  nullable = false
}

variable "hybrid_dns" {
  description = "Hybrid DNS, used only when the VPN or an Interconnect is on. enable_inbound_forwarding (default true) adds an inbound DNS policy on the hub VPC, so on-premises resolvers can forward the internal domain to its addresses. forward_zones forwards on-premises domains (dns_name ending with a dot) from the hub VPC to target_ips."
  type = object({
    enable_inbound_forwarding = optional(bool, true)
    forward_zones = optional(map(object({
      dns_name   = string
      target_ips = list(string)
    })), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for z in values(var.hybrid_dns.forward_zones) : endswith(z.dns_name, ".") && length(z.target_ips) > 0])
    error_message = "hybrid_dns.forward_zones entries need a dns_name ending with a dot and at least one target IP."
  }
}
```

Locals (add to the `locals` block at `main.tf:1-58`):

```hcl
  hybrid_enabled = var.vpn.enabled || length(var.interconnects) > 0

  # DEFAULT BGP mode announces only the hub's own subnets, never the peered
  # environments (ARC-12). An empty list falls back to hub + environment CIDRs.
  default_hybrid_advertised_ranges = concat(
    [{ range = var.hub_vpc_cidr_block, description = "hub VPC" }],
    var.hybrid_advertised_ranges,
  )
  vpn_effective = merge(var.vpn, {
    advertised_ip_ranges = length(var.vpn.advertised_ip_ranges) > 0 ? var.vpn.advertised_ip_ranges : local.default_hybrid_advertised_ranges
  })
  interconnects_effective = {
    for k, ic in var.interconnects : k => merge(ic, {
      advertised_ip_ranges = length(ic.advertised_ip_ranges) > 0 ? ic.advertised_ip_ranges : local.default_hybrid_advertised_ranges
    })
  }
```

In `module "hub"` use `vpn = local.vpn_effective` and `interconnects = local.interconnects_effective`. After `module "dns_anchor"` add:

```hcl
# Inbound DNS on the hub VPC: on-premises resolvers forward the internal
# domain to these addresses; the hub VPC sees internal-root (Task 4). A VPC
# takes one DNS policy, and nothing else attaches one to the hub.
resource "google_dns_policy" "hub_inbound" {
  count = local.hybrid_enabled && var.hybrid_dns.enable_inbound_forwarding ? 1 : 0

  project                   = var.hub_project_id
  name                      = "${var.project_prefix}-hub-inbound"
  description               = "Inbound forwarding for on-premises resolvers (hybrid DNS)."
  enable_inbound_forwarding = true
  enable_logging            = true

  networks {
    network_url = module.hub.network_self_link
  }
}

# On-premises domains, forwarded from the hub VPC over the VPN/Interconnect.
module "hybrid_forward_zones" {
  source   = "../../network/dns"
  for_each = local.hybrid_enabled ? var.hybrid_dns.forward_zones : {}

  project_id                  = var.hub_project_id
  zone_name                   = "fwd-${each.key}"
  dns_name                    = each.value.dns_name
  description                 = "Forward ${each.value.dns_name} to on-premises resolvers."
  visibility                  = "private"
  private_visibility_networks = [module.hub.network_self_link]
  forwarding_targets          = each.value.target_ips
  enable_logging              = true
}
```

Root: add variable `hybrid_dns` (same type, `default = null`) and config key `gcp.network.hybrid_dns` (`cfg.hybrid_dns = try(jsonencode(local.lz.gcp.network.hybrid_dns), null)`, effective `jsondecode(var.hybrid_dns != null ? jsonencode(var.hybrid_dns) : coalesce(local.cfg.hybrid_dns, "{}"))`). Pass to the stage:

```hcl
  hybrid_dns = local.hybrid_dns
  hybrid_advertised_ranges = [
    for k in sort(keys(local.environments)) : { range = local.environments[k].cidr_block, description = "environment ${k}" }
    if local.environments[k].cidr_block != ""
  ]
```

Schema `gcp.network.hybrid_dns`: object with `enable_inbound_forwarding` (boolean) and `forward_zones` (object of `{dns_name: string pattern "\\.$", target_ips: array of IPv4 strings}`), `additionalProperties: false`.

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/gcp/stages/network-hub modules/gcp/stages/net-hub envs/gcp/network-hub" TERRAFORM=$TF`, `make config-check`. Expected: pass.

- [ ] **Step 5: Docs.** `make docs`. `docs/runbooks/gcp-hybrid-connectivity.md`: add "Routes announced" (hub + environment CIDRs by default) and "DNS" (inbound policy addresses from `gcloud compute addresses list --filter=purpose=DNS_RESOLVER`; forward zones from `gcp.network.hybrid_dns.forward_zones`). UPGRADING entry under `### GCP`: "An estate with the VPN or an Interconnect and no `advertised_ip_ranges` switches the router to CUSTOM: it now announces the hub CIDR and every environment CIDR instead of the hub subnets. Set `advertised_ip_ranges` to keep the old announcement. A DNS inbound policy is added to the hub VPC." CHANGELOG bullet.

- [ ] **Step 6: Commit.** `git commit -m "feat(gcp-network)!: advertise environment ranges and add hybrid DNS on the hub"`

---

### Task 16: Cloud Run probes and a warm instance in production (ARC-16)

**Files:**
- Modify: `modules/gcp/compute/cloud-run/main.tf:66-100` (containers), `modules/gcp/compute/cloud-run/variables.tf:117-130` (new variable)
- Modify: `modules/gcp/compute/cloud-run/tests/plan_assertions.tftest.hcl`
- Modify: `modules/gcp/stages/app-services/variables.tf:213-235` (`services` type), `modules/gcp/stages/app-services/main.tf:284-300`
- Modify: `modules/gcp/stages/app-services/tests/plan_assertions.tftest.hcl`
- Modify: `modules/gcp/stages/environment/variables.tf:393,410` (key allowlists)
- Modify: `config/landing-zone.schema.json:531-560` (gcp services), `config/landing-zone.example.yaml:218`

- [ ] **Step 1: Write the failing tests.** Append to `modules/gcp/compute/cloud-run/tests/plan_assertions.tftest.hcl`:

```hcl
run "health_check_path_adds_startup_and_liveness_probes" {
  command = plan

  variables {
    health_check_path = "/healthz"
  }

  assert {
    condition = (
      google_cloud_run_v2_service.this.template[0].containers[0].startup_probe[0].http_get[0].path == "/healthz" &&
      google_cloud_run_v2_service.this.template[0].containers[0].liveness_probe[0].http_get[0].path == "/healthz" &&
      google_cloud_run_v2_service.this.template[0].containers[0].startup_probe[0].timeout_seconds <= google_cloud_run_v2_service.this.template[0].containers[0].startup_probe[0].period_seconds
    )
    error_message = "A health_check_path must add an HTTP startup and liveness probe."
  }
}

run "no_path_keeps_the_platform_default_probe" {
  command = plan

  assert {
    condition     = length(google_cloud_run_v2_service.this.template[0].containers[0].liveness_probe) == 0
    error_message = "Without a path the module must not add an HTTP probe the image may not serve."
  }
}
```

Append to `modules/gcp/stages/app-services/tests/plan_assertions.tftest.hcl`:

```hcl
run "production_services_stay_warm_and_probed" {
  command = plan

  variables {
    is_production = true
    services      = { api = {} }
  }

  assert {
    condition     = module.service["api"].min_instance_count_effective == 1
    error_message = "A production Cloud Run service without min_instances must keep one warm instance (ARC-16)."
  }

  assert {
    condition     = local.cloud_run_services["api"].health_check_path == "/"
    error_message = "Services default to probing / (the bootstrap image serves it)."
  }
}

run "non_production_still_scales_to_zero" {
  command = plan

  variables {
    services = { api = {} }
  }

  assert {
    condition     = module.service["api"].min_instance_count_effective == 0
    error_message = "Non-production services keep scale-to-zero by default."
  }
}
```

If a service entry needs more fields than `{}` in this stage, copy them from the `services` value at `plan_assertions.tftest.hcl:48`.

- [ ] **Step 2: Run.** `make test TEST_DIRS="modules/gcp/compute/cloud-run modules/gcp/stages/app-services" TERRAFORM=$TF`. Expected: undeclared `var.health_check_path` and output `min_instance_count_effective`.

- [ ] **Step 3: Implement.** `cloud-run/variables.tf`:

```hcl
variable "health_check_path" {
  description = "HTTP path for a startup probe (up to 120 s to become ready) and a liveness probe (every 30 s) on the container port. Null (default) keeps Cloud Run's default TCP startup probe."
  type        = string
  default     = null

  validation {
    condition     = var.health_check_path == null || startswith(coalesce(var.health_check_path, "/"), "/")
    error_message = "health_check_path must start with /."
  }
}
```

`cloud-run/main.tf`, inside `containers` after `resources`:

```hcl
      dynamic "startup_probe" {
        for_each = var.health_check_path == null ? [] : [var.health_check_path]
        content {
          initial_delay_seconds = 0
          period_seconds        = 5
          timeout_seconds       = 3
          failure_threshold     = 24

          http_get {
            path = startup_probe.value
          }
        }
      }

      dynamic "liveness_probe" {
        for_each = var.health_check_path == null ? [] : [var.health_check_path]
        content {
          period_seconds    = 30
          timeout_seconds   = 5
          failure_threshold = 3

          http_get {
            path = liveness_probe.value
          }
        }
      }
```

Add output `min_instance_count_effective = var.min_instance_count` to `cloud-run/outputs.tf` with description "Minimum instance count the service runs with.". In `app-services/variables.tf` change `min_instances = optional(number, 0)` to `min_instances = optional(number)` with the comment `# Null = 1 in production (var.is_production), 0 elsewhere.` and add `health_check_path = optional(string, "/")`. In `app-services/main.tf:294`:

```hcl
  min_instance_count = coalesce(each.value.min_instances, var.is_production ? 1 : 0)
  # An optional attribute with a default turns null into "/", so "" opts out.
  health_check_path = each.value.health_check_path == "" ? null : each.value.health_check_path
```

Extend the `is_production` description: "...and keeps one warm Cloud Run instance for every service whose min_instances is unset." Add `"health_check_path"` to both key allowlists at `modules/gcp/stages/environment/variables.tf:393` and `:410`. Schema: add `"health_check_path": {"type": "string", "pattern": "^/"}` next to `min_instances`. Example config line 218: add `#     health_check_path: /healthz`.

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/gcp/compute/cloud-run modules/gcp/stages/app-services modules/gcp/stages/environment envs/gcp/workload" TERRAFORM=$TF`, `make config-check`. Expected: pass.

- [ ] **Step 5: Docs.** `make docs`. UPGRADING entry under `### GCP`: "Production Cloud Run services without `min_instances` now keep one instance warm (billed idle). Every service gets HTTP probes on `health_check_path` (default `/`); set it to your health route, or to an empty string to keep the TCP probe. The change rolls a new revision with the deployed image (the image is ignored by Terraform)." CHANGELOG bullet.

- [ ] **Step 6: Commit.** `git commit -m "feat(gcp-app-services)!: probe Cloud Run services and keep production warm"`

---

### Task 17: ECS services autoscale in production by default (ARC-16)

**Files:**
- Modify: `modules/aws/stages/app-services/variables.tf:120-145` (`services` type), add `is_production`
- Modify: `modules/aws/stages/app-services/main.tf:747-751`
- Modify: `modules/aws/stages/app-services/tests/plan_assertions.tftest.hcl`
- Modify: `envs/aws/workload/variables.tf:411` (type), new `is_production` variable, `envs/aws/workload/config.tf:28-36`, `envs/aws/workload/main.tf:171-203`
- Modify: `docs/known-gaps.md`

- [ ] **Step 1: Write the failing test.** Append to `modules/aws/stages/app-services/tests/plan_assertions.tftest.hcl` (reuse the file's variables and any `override_module` for the ALB; copy the `services` value of its first run that plans one service):

```hcl
run "production_services_autoscale_by_default" {
  command = plan

  variables {
    is_production = true
    services      = { api = {} }
  }

  assert {
    condition     = length(module.service["api"].autoscaling_target_ids) == 1
    error_message = "A production ECS service without enable_autoscaling must scale on CPU (ARC-16)."
  }
}

run "non_production_autoscaling_stays_opt_in" {
  command = plan

  variables {
    services = { api = {} }
  }

  assert {
    condition     = length(module.service["api"].autoscaling_target_ids) == 0
    error_message = "Non-production services keep a fixed task count unless enable_autoscaling is set."
  }
}
```

The stage calls `ecs-fargate` as `module "service"` (`main.tf:697-699`). Add to `modules/aws/compute/ecs-fargate/outputs.tf`:

```hcl
output "autoscaling_target_ids" {
  description = "IDs of the Application Auto Scaling targets (empty when enable_autoscaling is false)."
  value       = aws_appautoscaling_target.this[*].id
}
```

- [ ] **Step 2: Run.** `make test TEST_DIRS=modules/aws/stages/app-services TERRAFORM=$TF`. Expected: undeclared `var.is_production`.

- [ ] **Step 3: Implement.** Stage variable:

```hcl
variable "is_production" {
  description = "Production environment: every service whose enable_autoscaling is unset scales on CPU between autoscaling_min_capacity and autoscaling_max_capacity."
  type        = bool
  default     = false
  nullable    = false
}
```

In the `services` type (stage and `envs/aws/workload/variables.tf:411`) change `enable_autoscaling = optional(bool, false)` to `enable_autoscaling = optional(bool) # null = on in production`. Stage `main.tf:749`: `enable_autoscaling = coalesce(each.value.enable_autoscaling, var.is_production)`. Root: add

```hcl
variable "is_production" {
  description = "Production environment (ECS autoscaling defaults on). Null = aws.workload_environments.<environment>.is_production from config/landing-zone.yaml, else true for an environment named prod or production."
  type        = bool
  default     = null
}
```

`config.tf` `cfg`: `workload_is_production = { for env, e in try({ for k, v in local.lz.aws.workload_environments : k => v }, {}) : env => tobool(e.is_production) if try(e.is_production, null) != null }` and the effective local `is_production = coalesce(var.is_production, try(local.cfg.workload_is_production[local.environment], null), can(regex("^prod(uction)?$", local.environment)))`. Pass `is_production = local.is_production` to `module "app_services"`.

- [ ] **Step 4: Run.** `make test TEST_DIRS="modules/aws/compute/ecs-fargate modules/aws/stages/app-services envs/aws/workload" TERRAFORM=$TF`. Expected: pass.

- [ ] **Step 5: Docs.** `make docs`. Add to `docs/known-gaps.md` `## OPEN`: "An autoscaled ECS service that Terraform deploys itself (no GitHub deploy role, so `enable_external_deployments` is false) has its `desired_count` reset on every apply. Services with a deploy role ignore it." UPGRADING entry under `### AWS`: "Production ECS services without `enable_autoscaling` now get a CPU target-tracking policy (2 to 10 tasks). Set `enable_autoscaling: false` to keep a fixed count." CHANGELOG bullet.

- [ ] **Step 6: Commit.** `git commit -m "feat(aws-app-services)!: autoscale production ECS services by default"`

---

## Sandbox proof

Mock tests prove plan shape only. Each task is proven by the live check below. "E2E" means `tests/e2e/<cloud>` (one disposable account or project, `terraform test` with `command = apply`, see `docs/guides/sandbox-e2e.md`); add the listed run in the same PR as the task. "Estate" means the sandbox estate (`docs/guides/sandbox-estate.md`, profile `starter`, GCP `dev`, AWS `workload_dev`); record the result in the release's sandbox upgrade log in `UPGRADING.md`.

| Task | Check | Where |
|---|---|---|
| 1 | Add to `tests/e2e/aws/main.tf`: an `aws_vpc_ipam` with `tier = "free"` and `cascade = true`, a pool and pool CIDR `10.248.0.0/14`, and a second `module "vpc"` with `ipam_pool_id`, `cidr_block = "10.249.0.0/16"` (explicit_cidr default) and one subnet. Assert in `e2e.tftest.hcl`: `data.aws_vpc.ipam.cidr_block == "10.249.0.0/16"` and the subnet exists with `10.249.0.0/24`. Add `ec2:*Ipam*` and `ec2:*IpamPool*` to the e2e role permissions in `sandbox-e2e.md`. Estate: a plan of `aws-workload-dev` after upgrade shows no VPC change. | E2E + Estate |
| 2 | Same e2e IPAM: add an `aws_vpc_ipam_pool_cidr_allocation` for `10.250.0.0/16` and assert that a `netmask_length = 16` allocation from the pool (`aws_vpc_ipam_pool_cidr_allocation` with `netmask_length`) does not return `10.250.0.0/16`. Estate: `aws ec2 get-ipam-pool-allocations` lists both hub CIDRs. | E2E + Estate |
| 3 | Plan-only; mock tests are the proof (tfc-admin reads only the config file). | None needed |
| 4 | Estate: from a VM in the `dev` spoke private subnet, `dig +short <record>.<internal_domain>` returns the record created in `internal-root`; `gcloud dns managed-zones describe internal-root` lists both networks; the `gcp-workload-dev` apply creates `internal-peering` without a 403. The e2e harness cannot hold this: it needs a VM and a DNS query from inside the VPC. | Estate |
| 5 | E2E: the existing AWS run passes in a non-eu-west-2 region (`E2E_AWS_REGION=us-east-1`) because it already passes region zones. | E2E |
| 6 | E2E: in the new IPAM run, choose the zone by ID (`data.aws_availability_zones.available.zone_ids[0]`, mapped to its name as in `envs/aws/network/azs.tf`) and assert `data.aws_subnet.ipam.availability_zone_id` equals it. Estate: set `aws.network.availability_zone_ids` in `config/sandbox/landing-zone.yaml` and confirm the hub and `workload_dev` subnets report the same AZ IDs (`aws ec2 describe-subnets --query 'Subnets[].AvailabilityZoneId'` in each account). | E2E + Estate |
| 7 | Estate: `aws route53profiles list-profile-resource-associations` shows the firewall rule group and the endpoint zones, and no VPC. With `enable_resolver_endpoints = true` for one run, both endpoints reach `OPERATIONAL`. | Estate |
| 8 | Estate: from an SSM-managed instance in `workload_dev` (or a CloudShell VPC environment in the spoke), `nslookup ssm.<region>.amazonaws.com` returns an address in the egress VPC, and `aws ssm describe-instance-information --endpoint-url https://ssm.<region>.amazonaws.com` succeeds with no NAT route. | Estate |
| 9 | Estate: `aws route53profiles list-profile-associations` in the `workload_dev` account shows the spoke VPC `COMPLETE`; a query for a blocked test domain (add `blocked.example.` to `blocked_domains` in the sandbox) returns NXDOMAIN from the spoke. | Estate |
| 10 | Estate (starter profile): after listing `dev` in `aws.network.spoke_attachments`, `curl -sI https://aws.amazon.com` from the spoke succeeds, and VPC flow logs show the NAT gateway as the path. | Estate |
| 11 | Estate needs a second spoke: add a temporary `workload_prod` spoke (segment `prod`) for one run, and confirm `ping`/`nc` from `dev` to it times out while egress still works; `aws ec2 search-transit-gateway-routes` shows the blackhole. Remove it after the run. | Estate |
| 12 | E2E: in the IPAM run, provision a second pool CIDR (`regional_additional_cidrs` shape) and allocate from it. The OU share needs an organization, so the share scope is an Estate check: an account outside the listed OU cannot see the pool (`aws ec2 describe-ipam-pools` from that account). | E2E + Estate |
| 13 | Docs only. | None needed |
| 14 | Estate: add a GCP environment `qa`; after its first workload apply the `hub_peering_active` check warns and `hub_peering_state` is `INACTIVE`; after the `gcp-network-hub` run it is `ACTIVE` and the check passes. | Estate |
| 15 | Estate with an HA VPN to a test peer (for example a second GCP project acting as on-premises): `gcloud compute routers get-status` lists the advertised hub and environment ranges; from the peer, `dig @<inbound-policy-IP> <record>.<internal_domain>` answers. | Estate |
| 16 | Add to `tests/e2e/gcp`: a `module "cloud_run"` from `modules/gcp/compute/cloud-run` with the public hello image, `health_check_path = "/"`, `min_instance_count = 1`, `deletion_protection = false`. Assert from `data.google_cloud_run_v2_service` that the latest ready revision has the startup and liveness probes and `scaling[0].min_instance_count == 1`. Add `run.googleapis.com` and `roles/run.admin` to the e2e project setup in `sandbox-e2e.md`. | E2E |
| 17 | Estate: with `workload_dev` marked `is_production: true` for one run, `aws application-autoscaling describe-scalable-targets --service-namespace ecs` lists the service with min 2, max 10. | Estate |
