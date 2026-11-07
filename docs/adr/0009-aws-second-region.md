# ADR 0009: AWS second region as a second network workspace

- Status: Proposed
- Date: 2026-11-07

## Context

Both clouds are single-region by default (`org.regions.aws`, `aws.enabled_regions` drives only IPAM operating regions). Backups point at one region, and `envs/aws/network` is one hub in one region.

## Decision

A second AWS region would be a second `aws-network` workspace (a second instance of the same root with its own region and CIDR pool), not a multi-region root, because a provider region is fixed per configuration. Transit gateway peering and Route 53 would join the two hubs. This ADR is design only. Nothing implements it, and cross-region backup copy is a separate open item in [known gaps](../known-gaps.md) (A5).

## Consequences

- Each region has its own blast radius and state.
- Extra workspaces and tfc-admin config when implemented.
- Until implemented, forks needing DR in a second region must build it themselves.
