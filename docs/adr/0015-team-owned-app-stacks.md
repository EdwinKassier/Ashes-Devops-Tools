# ADR 0015: Team-owned app stacks consume the environment contract

- Status: Proposed
- Date: 2026-11-11

## Context

Today one `gcp-workload-<env>` (or `aws-workload-<env>`) root owns the environment network, the VPC-SC perimeter, the budget and every app service in that environment. The services are listed in `config/landing-zone.yaml` (`gcp.environments.<env>.services`, `aws.workload_environments.<env>.services`). That file needs platform and security approval in CODEOWNERS.

So adding one Cloud Run or ECS service:

- needs a platform-reviewed edit to the central config file;
- re-plans the whole environment, network included;
- can block network changes for the environment when the service config is wrong;
- runs with the environment apply identity, which can change the network.

The 2026 golden-path pattern is the opposite: the platform publishes a contract, and each team owns a small stack that consumes it.

## Decision

Add per-team app roots, `envs/gcp/app` and `envs/aws/app`, one workspace per team and environment (`gcp-app-<env>-<team>`, `aws-app-<env>-<team>`):

1. The workload root publishes an environment contract output: host project or account, subnets, Shared VPC or TGW wiring, the KMS keys, the Artifact Registry or ECR repository, and the runtime service accounts the team may use. It is typed like the other contracts (ADR 0003).
2. Each app root reads that contract and calls `modules/gcp/stages/app-services` or `modules/aws/stages/app-services` with the team's services. The services live in the team's own file, `config/apps/<env>/<team>.yaml`. CODEOWNERS for that path is the team.
3. Each app workspace gets its own plan and apply identity, from `gcp-bootstrap` and `aws-organization`. That identity is scoped to the team's service project or account, and it has no network or IAM-admin role on the environment.
4. tfc-admin derives the app workspaces from `config/apps/**`, with run triggers from the workload workspace.
5. `services` under `landing-zone.yaml` stays supported during migration. The plan fails when the same service is declared in both places.

## Consequences

- A service change re-plans one team stack, not the environment, and needs only the team's review.
- The environment apply identity no longer deploys app code.
- More workspaces and identities, generated from config, not written by hand.
- Moving existing services needs `moved` blocks across states: use `removed` (destroy = false) in the workload root and `import` in the app root. A runbook must cover this.
- Until this ADR is implemented, keep services in the workload root. Review service-only PRs with that blast radius in mind.
