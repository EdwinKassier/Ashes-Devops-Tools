# tfc-admin token: creation and 90-day rotation

`envs/tfc-admin` manages the workspace layer (projects, workspaces, variable
sets, policy sets, run triggers, team access). It creates no teams and sets no
organization access, so it does not need an organization-owner token. It runs on
a **team token** of a dedicated `tfc-admin` team. The token is created by hand by
an owner, expires after 90 days, and exists only as tfc-admin's sensitive
`TFE_TOKEN` workspace variable (it never enters state or code).

## 1. Create the team (an organization owner, once)

Organization settings -> Teams -> Create a team named `tfc-admin`, with these
organization access flags and no others:

| Flag | Why tfc-admin needs it |
|------|------------------------|
| `manage_workspaces` | `tfe_workspace`, `tfe_workspace_settings`, `tfe_variable`, `tfe_run_trigger`, notification configurations, `tfe_team_access` on workspaces |
| `manage_projects` | `tfe_project`, `tfe_team_project_access`, and project-scoped workspace and variable-set administration |
| `manage_policies` | `tfe_policy_set` (the OPA guardrails and destructive-change sets) |
| `manage_vcs_settings` | VCS-sourced workspaces and policy sets use the organization's OAuth/GitHub App connection |

It must **not** have:

- `manage_teams` (it includes membership management, so the holder could add itself to the owners team), or
- `manage_organization_access` (owner-equivalent), or
- `manage_policy_overrides` (applies organization-wide; overrides stay with the security team), or
- `manage_run_tasks`, `manage_providers`, `manage_modules` (unused).

Put the team ID into tfc-admin's `tfc_admin_team_id` variable. With
`manage_tfc_admin_workspace = true` this records an explicit write grant on the
tfc-admin workspace, and the root removes every other apply path to it: the
approvers team gets no grant on the project holding tfc-admin, and the platform
team is capped at `plan` there. Apply of tfc-admin is therefore confirmed by
organization owners and the `tfc-admin` team only. `auto_apply` is false and
speculative plans are off on that workspace.

Verify the flags on the first plan. If a resource fails with a permission error,
add only the flag named by the error and record it in this table; do not fall
back to an owners token. A variable set that the team cannot manage is the likely
case (see `docs/known-gaps.md`).

## 2. Create the token (an owner)

Team `tfc-admin` -> API tokens -> Create a team token with:

- a unique description, `tfc-admin <YYYY-MM-DD>` (the creation date), and
- `expired_at` 90 days out (the HCP UI offers 30 days, 60 days, 90 days or custom;
  via API set `expired-at` to now + 90d).

Store it as the sensitive environment variable `TFE_TOKEN` on the `tfc-admin`
workspace, and nowhere else (not in a password manager entry shared with CI, not in
tfvars, not in a repo). Calendar the expiry 14 days early.

## 3. Rotate (every 90 days, or on any suspected exposure)

Do these in order so tfc-admin never runs without a valid token:

1. Create a new team token with a new unique description and a fresh `expired_at`.
2. Update the workspace variable `TFE_TOKEN` on tfc-admin to the new token.
3. Queue a plan on tfc-admin to prove the new token works.
4. Revoke the old token (Team -> API tokens -> delete the one with the old
   description). A team has one token at a time per the UI; if the UI replaces the
   old one on creation, do step 1 and 2 back to back and run step 3 immediately.

After exposure, do 1 to 4 immediately and review the audit trail for the old token.

## 4. Phase-0

The very first tfc-admin apply is run with a temporary owner token (see
[bootstrap.md](bootstrap.md)). Revoke it as soon as the first apply succeeds and the
team token above is installed.
