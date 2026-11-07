# ADR 0011: Temporary elevated access to AWS accounts

- Status: Accepted
- Date: 2026-11-07

## Context

The landing zone grants standing access through IAM Identity Center permission
sets assigned to groups (`aws.identity.groups`, `envs/aws/identity`). Standing
administrator access is not acceptable for production, but engineers still need
time-boxed elevation (incident response, break-glass-adjacent changes) with
approval and an audit trail. Terraform manages assignments declaratively, so
per-request grants must not be written into this repository: they would churn
state and need a pull request per request.

## Decision

Use identity-provider-native access requests that add and remove members of
Identity Center groups already assigned by Terraform:

1. Define elevated groups (for example `Platform Admins`) in the external IdP
   and assign them to permission sets in `aws.identity.groups`.
2. Let the IdP govern membership with approval and expiry: Microsoft Entra
   Privileged Identity Management (PIM for Groups) or Okta Access Requests
   (Okta Identity Governance).
3. The IdP pushes group membership to Identity Center over SCIM. Terraform
   never sees individual users; it owns only the group-to-permission-set-to-
   account bindings.

Permission sets keep short `session_duration` values (`PT1H` to `PT4H` for the
administrative sets) so a revoked membership loses access quickly.

## Alternatives

- AWS Security Competency partner products (commercial temporary-elevated-access
  offerings) when the IdP lacks an access-request feature. Evaluate against the
  same SCIM-group model.
- TEAM (Temporary Elevated Access Management) is an aws-samples project, not an
  AWS product or service. It writes per-request assignments through its own
  backend, so it is self-hosted software with its own operations, upgrades and
  security review. Adopt it only if that ownership is accepted; it also writes
  account assignments that Terraform does not manage, so keep its permission
  sets and groups out of `aws.identity.groups`.

## Consequences

- No new Terraform resources: elevation is membership of an existing group.
- Access reviews and approvals live in the IdP; CloudTrail records the resulting
  sign-ins and role sessions.
- Requires the IdP to provision groups to Identity Center via SCIM.
