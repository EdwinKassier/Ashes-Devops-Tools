# ADR 0010: Repo-wide tags and labels

- Status: Accepted
- Date: 2026-11-07

## Context

Cost allocation and ownership need consistent tags, but many modules do not accept a `tags` input, and AWS tag keys differ in allowed characters from GCP label keys.

## Decision

Set tags at the provider, not per module. Each AWS root's `provider "aws"` has `default_tags` (`ManagedBy`, `LandingZone`, `Workspace`, `Environment`, `CostCenter`, `Owner`), with `CostCenter` and `Owner` taken from `org.cost_center` and `org.owner` in `config/landing-zone.yaml`. Each GCP root sets `default_labels` (`managed-by`, `landing-zone`, `workspace`, `environment`). Stages add stage-specific extras through their `tags` input. The AWS organization applies a tag policy of required tags, and the `require_labels` OPA policy checks listed types.

## Consequences

- Every taggable resource is labelled without per-module plumbing.
- Key casing differs by cloud (`CostCenter` versus `landing-zone`) because the platforms' key rules differ.
- Modules that create untaggable or provider-ignored resources are not covered.
