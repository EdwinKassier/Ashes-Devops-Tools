# config/sandbox: the sandbox estate

This directory holds the committed config for the **sandbox estate**. The estate is a
second tfc-admin instance in its own HCP Terraform organization. It applies every merge
to `main` on top of the previous `main`, so each merge is tested as an upgrade before a
release. The full guide is [docs/guides/sandbox-estate.md](../../docs/guides/sandbox-estate.md).

| File | Read by |
|------|---------|
| `landing-zone.yaml` | The sandbox tfc-admin (`landing_zone_config_path = "../../config/sandbox/landing-zone.yaml"`) and every sandbox workspace, through the next file |
| `tfc-workspaces.yaml` | The sandbox tfc-admin (`workspace_variables_file = "../../config/sandbox/tfc-workspaces.yaml"`). It points each workspace's `landing_zone_config_path` here |

Every value is a placeholder (`my-sandbox-org`, `REPLACE_WITH_*`, `example.com`). Replace
them before the first sandbox apply. `make config-check` validates `landing-zone.yaml`
against `config/landing-zone.schema.json`.

Edits here queue **sandbox** runs only, because sandbox workspaces trigger on
`config/sandbox/**`. Production workspaces trigger on `config/landing-zone.yaml` and
`config/tfc-workspaces.yaml`, never on this directory.

**Forks may delete this directory.** A fork that runs no sandbox estate does not need it,
and nothing in production reads it. If you delete it, also delete the
`sandbox_config_files_plan` run in `envs/tfc-admin/tests/sandbox.tftest.hcl`, which plans
these files. NO SECRETS: both files are committed.
