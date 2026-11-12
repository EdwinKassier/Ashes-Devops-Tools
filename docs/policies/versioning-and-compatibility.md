# Versioning and Compatibility Policy

This policy says what a release version promises, what counts as a breaking
change, how long a release line gets fixes, and how to pin this repository. It
applies to every module under `modules/`, every root under `envs/` and the
configuration schema in `config/landing-zone.schema.json`.

## One version for the whole repository

The repository has one [Semantic Versioning](https://semver.org/) number,
`vX.Y.Z`. release-please cuts it from Conventional Commits
(`release-please-config.json`, `.github/workflows/release.yml`); until the
release GitHub App exists, a maintainer tags releases by hand with the same
rules (`README.md`, "Releasing"). All modules and
roots share it: a release is one tested set, and every module in it was tested
with every other module at that commit.

The **public API** is:

- every module's input variables (name, type, and whether it is required) and
  outputs (name and value shape);
- every root's input variables and outputs;
- every key of `config/landing-zone.yaml` that the schema accepts;
- the module paths under `modules/` that consumers reference in `source`.

Everything else is internal: resource addresses inside a module, locals, file
layout inside a module directory, test files, examples, scripts and workflows.
A change to resource addresses that would destroy and recreate a resource is
still a breaking change for the estate. It needs a `moved` block, or a
breaking-change commit with an `UPGRADING.md` entry.

## What is a breaking change

A change is breaking when a consumer that pins the previous release must edit
their code or configuration, or would get a different plan, to take the new
release. Examples:

- removing or renaming an input, an output, a config key or a module path;
- making an optional input required, or narrowing its type or its validation;
- changing a default so that an existing configuration plans a different
  result;
- raising the minimum Terraform version (`required_version`, today
  `>= 1.17, < 2.0`) or moving a provider to a new major version.

Adding an optional input, an output, a config key or a module is not breaking.

Every breaking change carries a `type!:` subject or a `BREAKING CHANGE:` footer
in its commit, and an entry under `Unreleased` in `UPGRADING.md` in the same
pull request. CI enforces this in the meta-lint job:

| Rule | Check | Local equivalent |
|---|---|---|
| A breaking commit updates `UPGRADING.md` | "Breaking-change commits must update UPGRADING.md" | `make commit-check` |
| Removing or renaming a module input or output, or deleting a module, is marked breaking | `scripts/check-module-api.sh` | `make module-api` |

The module API check compares each changed module directory under `modules/`
between the pull request's merge-base and its head. It does not yet check
roots, config keys, types, defaults or validations: reviewers check those by
hand.

### Prefer deprecation to removal

Before you remove an input, mark it with Terraform's `deprecated` argument for
at least one minor release, name the replacement, and keep it working. Remove
it in a later release with a breaking-change commit. `envs/aws/workload` has
examples.

## Version numbers before and after 1.0

| Phase | Breaking changes | Features | Fixes |
|---|---|---|---|
| `0.y.z` (now) | Minor bump (`0.1.0` to `0.2.0`), each with an `UPGRADING.md` entry | Minor bump | Patch bump |
| `1.0.0` and later | Major bump only | Minor bump | Patch bump |

release-please applies this: `bump-minor-pre-major` is `true`, so a breaking
commit before 1.0 bumps the minor version.

## Support window

- The latest minor release line gets every fix.
- The previous minor release line gets security fixes for 90 days after the
  next minor release is published.
- Older lines get no fixes. Upgrade one minor release at a time, oldest first,
  and follow each `UPGRADING.md` section.

## Provider and Terraform floors

Each module and root pins its providers to one major version with a floor, as
listed in `CLAUDE.md` ("Toolchain Requirements"). For example `hashicorp/aws`
`>= 6.46.0, < 7.0.0` and `hashicorp/google` `~> 8.0`. The rules:

- A floor rises only when the code needs a newer provider feature or fix. The
  commit says why, and `UPGRADING.md` lists it when the consumer must update a
  lockfile.
- A new provider major version is a deliberate, tested change
  (`docs/guides/provider-upgrades.md`), never an automatic one. Renovate does
  not propose provider majors (`renovate.json`).
- Lockfiles hold one version of each provider across the repository, for
  `linux_amd64`, `darwin_arm64` and `darwin_amd64`
  (`scripts/check-consistency.sh`).

## How to consume this repository

Pin a release tag in every module `source`, never a branch:

```hcl
module "organization" {
  source = "git::https://github.com/<owner>/<repo>.git//modules/gcp/stages/organization?ref=vX.Y.Z"
}
```

Use the same tag for every module from this repository, because a release is
tested as one set. To upgrade, read each `UPGRADING.md` section between your tag
and the new one, change the tag everywhere, and run a plan before the apply.
A fork takes releases by merging the tag (`UPGRADING.md`, "Merging a release
tag").

## Rejected option: a version per module

Decision D9 considered tagging each module separately in a module registry
(for example `modules/gcp/network/vpc/v1.4.0`). It was rejected for now:

- The modules are built and tested as one landing zone. Stages compose many
  modules through relative paths, so independent versions would mean testing
  combinations that nobody runs.
- One maintainer cannot keep up a release line, a changelog and a support
  window for each of more than one hundred modules.
- Consumers deploy the landing zone as a whole, not single modules.

Revisit this when one of these becomes true: external teams consume single
modules outside the landing zone, a module needs a release cadence of its own,
or the project has enough maintainers to own per-module release lines.
