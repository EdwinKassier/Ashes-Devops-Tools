.PHONY: help install fmt fmt-check validate validate-all lint consistency security security-low security-report docs docs-check count count-check links examples-refs required-checks required-checks-live backend-check cfn-lint shellcheck test test-scripts ci ci-quick yamllint markdownlint-check commit-check module-usage opa-test codeowners-check clean clean-locks init-gcp-organization init-gcp-workload plan-gcp-organization plan-gcp-workload plan-aws-workload apply-gcp-organization apply-gcp-workload validate-requirements pre-commit-install pre-commit-run pre-commit-update state-list-gcp-organization state-list-gcp-workload state-rm-gcp-organization state-rm-gcp-workload unlock-gcp-organization unlock-gcp-workload

TERRAFORM := terraform
TFLINT := tflint
# Trivy replaces tfsec (EOL - Aqua folded it into Trivy). The version MUST match
# what reusable-security.yml runs (trivy-action `version:`), pinned in .tool-versions.
TRIVY := trivy
TRIVY_VERSION := $(shell awk '$$1=="trivy"{print $$2}' .tool-versions)
TRIVY_ARGS := config . --skip-dirs '**/.terraform'
SHELLCHECK_VERSION := $(shell awk '$$1=="shellcheck"{print $$2}' .tool-versions)
# OPA MUST match the version the `opa` job in terraform-plan.yml installs (OPA_VERSION there).
OPA_VERSION := $(shell awk '$$1=="opa"{print $$2}' .tool-versions)
# Checkov MUST match the version CI runs (checkov-action pins the image; keep
# .tool-versions in sync). Newer checkov ships new checks, so a skewed local
# binary gives a false green. Prefer an exact-version uvx run; otherwise the
# local binary is used and `make security` refuses to run on a version mismatch.
CHECKOV_VERSION := $(shell awk '$$1=="checkov"{print $$2}' .tool-versions)
CHECKOV := $(shell if command -v uvx >/dev/null 2>&1; then echo "uvx --python 3.12 checkov==$(CHECKOV_VERSION)"; else echo checkov; fi)
TERRAFORM_DOCS := terraform-docs
PRE_COMMIT := pre-commit
ROOT_DISCOVERY := ./scripts/terraform-roots.sh

# One shared provider cache for every `init` this Makefile runs. Without it each
# of the ~240 roots/modules/examples downloads its own copy of hashicorp/aws
# (~700 MB) and google, and `make ci` on a fresh clone can exhaust the disk.
# Override with your own TF_PLUGIN_CACHE_DIR; set it to "" to disable.
TF_PLUGIN_CACHE_DIR ?= $(HOME)/.terraform.d/plugin-cache
export TF_PLUGIN_CACHE_DIR
$(if $(TF_PLUGIN_CACHE_DIR),$(shell mkdir -p "$(TF_PLUGIN_CACHE_DIR)"))

APP_ENV ?= dev
APP_WORKSPACE ?= gcp-workload-$(APP_ENV)
APP_VARS ?=

BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m

TERRAFORM_ROOTS := $(shell $(ROOT_DISCOVERY) all)

help: ## Show available commands
	@echo '$(BLUE)Ashes DevOps Tools$(NC)'
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make <target>\n"} /^[a-zA-Z0-9_.%-]+:.*?##/ { printf "  $(BLUE)%-22s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

install: ## Install required local tooling
	@bash scripts/setup.sh

fmt: ## Format Terraform files
	@$(TERRAFORM) fmt -recursive .

fmt-check: ## Check Terraform formatting
	@$(TERRAFORM) fmt -recursive -check .

validate: ## Validate Terraform in the current working directory
	@$(TERRAFORM) validate

validate-all: ## Initialize without backends and validate every supported root
	@set -e; \
	for dir in $(TERRAFORM_ROOTS); do \
		echo "$(YELLOW)Validating $$dir$(NC)"; \
		for attempt in 1 2 3; do \
			if [ -d "$$dir/.terraform/providers" ]; then \
				$(TERRAFORM) -chdir=$$dir init -backend=false -input=false -upgrade=false -lockfile=readonly >/dev/null && break; \
			else \
				$(TERRAFORM) -chdir=$$dir init -backend=false -input=false >/dev/null && break; \
			fi; \
			[ $$attempt -lt 3 ] || exit 1; \
		done; \
		if grep -rqE 'configuration_aliases[[:space:]]*=' "$$dir" --include='*.tf'; then \
			echo "$(YELLOW)Skipping validate for $$dir (declares configuration_aliases; covered by examples/, composing roots and mock tests)$(NC)"; \
		else \
			$(TERRAFORM) -chdir=$$dir validate; \
		fi; \
	done

lint: ## Run TFLint across the repository
	@$(TFLINT) --init
	@set -e; \
	for dir in $(TERRAFORM_ROOTS); do \
		echo "$(YELLOW)Linting $$dir$(NC)"; \
		for attempt in 1 2 3; do \
			if [ -d "$$dir/.terraform/modules" ]; then \
				break; \
			else \
				$(TERRAFORM) -chdir=$$dir init -backend=false -input=false >/dev/null && break; \
			fi; \
			[ $$attempt -lt 3 ] || exit 1; \
		done; \
		$(TFLINT) --chdir=$$dir --config=$(PWD)/.tflint.hcl; \
	done

security: ## Run Trivy (IaC config) and checkov and fail on real findings
	@command -v $(TRIVY) >/dev/null 2>&1 || { \
		echo "trivy not found. Install trivy $(TRIVY_VERSION) (pinned in .tool-versions), e.g. 'asdf install trivy $(TRIVY_VERSION)'"; \
		echo "or see https://trivy.dev/latest/getting-started/installation/. tfsec is EOL and no longer used."; \
		exit 1; }
	@v="$$($(TRIVY) --version 2>/dev/null | awk '/^Version:/{print $$2; exit}')"; \
	if [ "$$v" != "$(TRIVY_VERSION)" ]; then \
		echo "trivy $$v does not match the CI-pinned $(TRIVY_VERSION) (.tool-versions). Install trivy $(TRIVY_VERSION)."; \
		exit 1; \
	fi
	@v="$$($(CHECKOV) --version 2>/dev/null | tail -1)"; \
	if [ "$$v" != "$(CHECKOV_VERSION)" ]; then \
		echo "checkov $$v does not match the CI-pinned $(CHECKOV_VERSION) (.tool-versions). Install uv or checkov==$(CHECKOV_VERSION)."; \
		exit 1; \
	fi
	# Same blocking gate as CI (reusable-security.yml). Trivy recurses the whole tree natively.
	@$(TRIVY) $(TRIVY_ARGS) --severity CRITICAL,HIGH --exit-code 1
	@$(CHECKOV) -d modules --quiet --compact --framework terraform --config-file .checkov.yaml
	@$(CHECKOV) -d envs --quiet --compact --framework terraform --config-file .checkov.yaml

security-low: ## Advisory-only: run Trivy at LOW+ severity across the full tree (non-blocking)
	@$(TRIVY) $(TRIVY_ARGS) --severity LOW,MEDIUM,HIGH,CRITICAL --exit-code 0

security-report: ## Generate detailed security reports
	@mkdir -p reports
	@$(TRIVY) $(TRIVY_ARGS) --format json --output reports/trivy-report.json --exit-code 0
	@$(CHECKOV) -d modules --framework terraform --output json --config-file .checkov.yaml > reports/checkov-modules-report.json
	@$(CHECKOV) -d envs --framework terraform --output json --config-file .checkov.yaml > reports/checkov-envs-report.json

docs: ## Generate Terraform docs from repo root
	@bash scripts/module-docs.sh generate

docs-check: ## Verify Terraform docs are up to date
	@bash scripts/module-docs.sh check

count: ## Print the live module/root/test-suite counts (the figures README.md and CLAUDE.md must quote) + library-only modules
	@./scripts/check-docs-counts.sh --print
	@python3 scripts/check-module-usage.py

count-check: ## Fail if README.md / CLAUDE.md counts drifted from the tree (CI: meta-lint)
	@./scripts/check-docs-counts.sh
	@python3 scripts/check-module-usage.py --check

examples-refs: ## Fail when a code snippet in examples/system-design cites a missing module, input, config key or envs/ path (offline; CI: meta-lint)
	@bash scripts/check-examples-refs.sh

links: ## Fail on broken repo-relative links in any Markdown file (offline; CI: meta-lint)
	@python3 scripts/check-md-links.py

required-checks-live: ## Diff BRANCH_PROTECTION.md against the LIVE branch protection (needs gh auth with repo admin)
	@./scripts/check-required-checks.sh --live

cfn-lint: ## Lint the shipped CloudFormation templates (templates/aws/bootstrap) with cfn-lint via uvx
	@uvx --python 3.12 cfn-lint templates/aws/bootstrap/*.yaml && echo "cfn-lint: templates OK"

backend-check: ## Real (credential-less) terraform init of every envs/** root — catches invalid backend/cloud blocks (CI: Terraform Format)
	@./scripts/check-backends.sh

required-checks: ## Fail if BRANCH_PROTECTION.md requires a status-check context no workflow job reports (CI: meta-lint)
	@./scripts/check-required-checks.sh

test-scripts: ## Run the shell-script tests in scripts/tests/ (CI: meta-lint)
	@set -e; for t in scripts/tests/test-*.sh; do echo "$(YELLOW)$$t$(NC)"; bash "$$t"; done

shellcheck: ## Run shellcheck (pinned shellcheck-py, same as pre-commit) on scripts/*.sh, scripts/tests/*.sh and tests/e2e/scripts/*.sh
	@if command -v uvx >/dev/null 2>&1; then \
		uvx --from shellcheck-py==$(SHELLCHECK_VERSION).1 shellcheck --severity=warning scripts/*.sh scripts/tests/*.sh tests/e2e/scripts/*.sh; \
	else \
		shellcheck --severity=warning scripts/*.sh scripts/tests/*.sh tests/e2e/scripts/*.sh; \
	fi

# TEST_DIRS overrides the discovered set (the CI test shards pass their slice):
#   make test TEST_DIRS="modules/gcp/network/vpc modules/gcp/governance/kms"
# Discovery (scripts/terraform-roots.sh tests) excludes tests/e2e, whose suites
# do REAL applies and run only in sandbox-e2e.yml.
test: ## Run terraform test suites (searches module roots and their tests/ subdirs)
	@set -e; \
	test_dirs="$(if $(TEST_DIRS),$(TEST_DIRS),$$($(ROOT_DISCOVERY) tests))"; \
	if [ -z "$$test_dirs" ]; then \
		echo "$(YELLOW)No terraform test suites found$(NC)"; \
		exit 0; \
	fi; \
	for dir in $$test_dirs; do \
		echo "$(YELLOW)Testing $$dir$(NC)"; \
		for attempt in 1 2 3; do \
			if [ -d "$$dir/.terraform/providers" ]; then \
				$(TERRAFORM) -chdir=$$dir init -backend=false -input=false -upgrade=false -lockfile=readonly >/dev/null && break; \
			else \
				$(TERRAFORM) -chdir=$$dir init -backend=false -input=false >/dev/null && break; \
			fi; \
			[ $$attempt -lt 3 ] || exit 1; \
		done; \
		$(TERRAFORM) -chdir=$$dir test; \
	done

pre-commit-install: ## Install git pre-commit hooks
	@$(PRE_COMMIT) install

pre-commit-run: ## Run pre-commit across the repository
	@$(PRE_COMMIT) run --all-files

pre-commit-update: ## Update pinned pre-commit hooks
	@$(PRE_COMMIT) autoupdate

consistency: ## Assert canonical strings (region regex, provider pins) haven't drifted across copies, and cross-root contracts (scripts/check-contracts.sh)
	@./scripts/check-consistency.sh
	@./scripts/check-contracts.sh

yamllint: ## yamllint exactly as CI: the pre-commit hook config, all files (CI: meta-lint)
	@command -v $(PRE_COMMIT) >/dev/null 2>&1 || { echo "pre-commit not found: pipx install pre-commit (or brew install pre-commit)"; exit 1; }
	@$(PRE_COMMIT) run yamllint --all-files

markdownlint-check: ## markdownlint as CI, check-only (manual-stage hook without --fix; never rewrites files) (CI: meta-lint)
	@command -v $(PRE_COMMIT) >/dev/null 2>&1 || { echo "pre-commit not found: pipx install pre-commit (or brew install pre-commit)"; exit 1; }
	@$(PRE_COMMIT) run markdownlint-check --all-files --hook-stage manual

# CI (meta-lint) checks the commits of the PR: merge-base with the base branch..HEAD.
COMMIT_BASE ?= origin/main
commit-check: ## Conventional-commit check and the UPGRADING.md rule for breaking commits, merge-base(COMMIT_BASE)..HEAD (CI: meta-lint)
	@command -v cz >/dev/null 2>&1 || { echo "cz (commitizen) not found: pipx install commitizen (CI uses .github/requirements/commitizen.txt)"; exit 1; }
	@git rev-parse --verify --quiet $(COMMIT_BASE) >/dev/null || { echo "$(COMMIT_BASE) not found: run 'git fetch origin main' or set COMMIT_BASE=<ref>"; exit 1; }
	@base="$$(git merge-base $(COMMIT_BASE) HEAD)" && [ -n "$$base" ] || { echo "no merge-base with $(COMMIT_BASE): fetch full history (git fetch --unshallow)"; exit 1; }; \
	if [ "$$base" = "$$(git rev-parse HEAD)" ]; then echo "commit-check: no commits ahead of $(COMMIT_BASE)"; exit 0; fi; \
	cz check --rev-range "$$base..HEAD" || exit 1; \
	if git log --format=%B "$$base..HEAD" | grep -Eq '^[a-z]+(\([^)]*\))?!:|^BREAKING[ -]CHANGE'; then \
		git diff --name-only "$$base..HEAD" | grep -qx 'UPGRADING.md' || { echo "A commit is marked breaking (!: or BREAKING CHANGE) but UPGRADING.md is not in the diff. Add an entry under 'Unreleased'."; exit 1; }; \
	fi; echo "commit-check: OK"

module-usage: ## Fail on unreferenced modules that are not marked library-only (CI: meta-lint)
	@python3 scripts/check-module-usage.py --check

opa-test: ## opa check --strict and opa test on both policy sets, at the CI-pinned version (CI: opa)
	@command -v opa >/dev/null 2>&1 || { echo "opa not found. Install opa $(OPA_VERSION) (pinned in .tool-versions): 'brew install opa' or 'mise install opa@$(OPA_VERSION)' or https://www.openpolicyagent.org/docs/latest/#running-opa"; exit 1; }
	@v="$$(opa version 2>/dev/null | awk '/^Version:/{print $$2; exit}')"; \
	if [ "$$v" != "$(OPA_VERSION)" ]; then echo "opa $$v does not match the CI-pinned $(OPA_VERSION) (.tool-versions). Install opa $(OPA_VERSION)."; exit 1; fi
	@opa check --strict policies/opa policies/opa-destructive
	@opa test policies/opa policies/opa-destructive

codeowners-check: ## Fail on @your-org/ placeholder owners when CODEOWNERS_ENFORCE=true; otherwise warn, as CI does (CI: codeowners)
	@if grep -nE '@your-org/' .github/CODEOWNERS; then \
		if [ "$${CODEOWNERS_ENFORCE:-false}" = "true" ]; then echo "CODEOWNERS still contains @your-org/ placeholder teams (CODEOWNERS_ENFORCE=true)."; exit 1; fi; \
		echo "warning: CODEOWNERS still contains @your-org/ placeholder teams (set CODEOWNERS_ENFORCE=true to make this fatal)."; \
	else echo "No placeholder owners found."; fi

ci-quick: ## Fast offline gates, no terraform init: fmt, consistency, config, scaffold fixtures, counts, links, refs, required checks, shellcheck, script tests, docs
	@$(MAKE) fmt-check
	@$(MAKE) consistency
	@$(MAKE) config-check
	@$(MAKE) scaffold-fixtures-check
	@$(MAKE) count-check
	@$(MAKE) links
	@$(MAKE) examples-refs
	@$(MAKE) required-checks
	@$(MAKE) shellcheck
	@$(MAKE) test-scripts
	@$(MAKE) docs-check

ci: ## Run the local CI pipeline: every workstation-runnable gate of terraform-plan.yml and reusable-security.yml (see make -n ci)
	@$(MAKE) ci-quick
	@$(MAKE) yamllint
	@$(MAKE) markdownlint-check
	@$(MAKE) commit-check
	@$(MAKE) codeowners-check
	@$(MAKE) backend-check
	@$(MAKE) validate-all
	@$(MAKE) lint
	@$(MAKE) test
	@$(MAKE) opa-test
	@$(MAKE) security

init-gcp-organization: ## Initialize the gcp-organization root
	@$(TERRAFORM) -chdir=envs/gcp/organization init

init-gcp-workload: ## Initialize the gcp-workload root
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp/workload init

plan-gcp-organization: ## Plan the gcp-organization root
	@$(TERRAFORM) -chdir=envs/gcp/organization plan

plan-gcp-workload: ## Plan gcp-workload-<APP_ENV> in HCP Terraform (read-only); APP_VARS=<file> adds a tuning -var-file
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp/workload plan $(if $(APP_VARS),-var-file=$(abspath $(APP_VARS)))

# Every other root: make plan-gcp-<root> / make plan-aws-<root>. Each root's
# backend.tf names its HCP Terraform workspace, so no TF_WORKSPACE is needed
# (the workload roots select theirs from APP_ENV). Explicit rules above win over
# these pattern rules.
GCP_PLAN_ROOTS := bootstrap organization guardrails projects network-hub
AWS_PLAN_ROOTS := organization security network identity shared-services backup

plan-aws-workload: ## Plan aws-workload-<APP_ENV> in HCP Terraform (read-only): make plan-aws-workload APP_ENV=dev
	@TF_WORKSPACE=aws-workload-$(APP_ENV) $(TERRAFORM) -chdir=envs/aws/workload plan

plan-gcp-%: ## Plan a GCP root in HCP Terraform (read-only): make plan-gcp-projects
	@case " $(GCP_PLAN_ROOTS) " in *" $* "*) ;; *) echo "Unknown GCP root '$*': one of $(GCP_PLAN_ROOTS), or plan-gcp-workload"; exit 1 ;; esac
	@$(TERRAFORM) -chdir=envs/gcp/$* plan

plan-aws-%: ## Plan an AWS layer root in HCP Terraform (read-only): make plan-aws-network
	@case " $(AWS_PLAN_ROOTS) " in *" $* "*) ;; *) echo "Unknown AWS root '$*': one of $(AWS_PLAN_ROOTS), or plan-aws-workload"; exit 1 ;; esac
	@$(TERRAFORM) -chdir=envs/aws/$* plan

apply-gcp-organization: ## Refuses: applies run in Terraform Cloud only (CLAUDE.md "State & Apply Rules")
	@echo "Local apply is not supported. gcp-organization is applied by Terraform Cloud:"
	@echo "merge to main (VCS-driven run) or queue a run on the gcp-organization workspace in TFC."
	@echo "Preview locally with: make plan-gcp-organization. Failed applies: docs/runbooks/apply-recovery.md"
	@exit 1

apply-gcp-workload: ## Refuses: applies run in Terraform Cloud only (CLAUDE.md "State & Apply Rules")
	@echo "Local apply is not supported. $(APP_WORKSPACE) is applied by Terraform Cloud:"
	@echo "merge to main (VCS-driven run) or queue a run on the $(APP_WORKSPACE) workspace in TFC."
	@echo "Preview locally with: make plan-gcp-workload APP_ENV=$(APP_ENV). Promotion: docs/runbooks/promotion.md"
	@exit 1

apply-gcp-% apply-aws-%: ## Refuses: applies run in Terraform Cloud only, for every root (CLAUDE.md "State & Apply Rules")
	@echo "Local apply is not supported. $(patsubst apply-%,%,$@) is applied by Terraform Cloud:"
	@echo "merge to main (VCS-driven run) or queue a run on its workspace in TFC."
	@echo "Preview locally with: make plan-$(patsubst apply-%,%,$@). Failed applies: docs/runbooks/apply-recovery.md"
	@exit 1

validate-requirements: ## Print local tool versions
	@$(TERRAFORM) version
	@$(TFLINT) --version
	@$(TRIVY) --version
	@$(CHECKOV) --version
	@$(TERRAFORM_DOCS) --version

state-list-gcp-organization: ## List resources in the gcp-organization workspace state
	@$(TERRAFORM) -chdir=envs/gcp/organization state list

state-list-gcp-workload: ## List resources in the gcp-workload workspace state (APP_ENV=dev)
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp/workload state list

state-rm-gcp-organization: ## Remove a resource from the gcp-organization state (DANGEROUS — orphans the GCP resource): make state-rm-gcp-organization ADDR='module.foo.resource.bar'
	@[ -n "$(ADDR)" ] || (echo "Error: ADDR is required. Usage: make state-rm-gcp-organization ADDR='module.foo.resource.bar'" && exit 1)
	@echo "$(YELLOW)WARNING: Removing '$(ADDR)' from state will ORPHAN this resource in GCP.$(NC)"
	@echo "$(YELLOW)The resource will continue to exist but Terraform will no longer manage it.$(NC)"
	@printf "Type 'yes' to confirm: " && read CONFIRM && [ "$$CONFIRM" = "yes" ] || (echo "Cancelled." && exit 1)
	@$(TERRAFORM) -chdir=envs/gcp/organization state rm '$(ADDR)'

state-rm-gcp-workload: ## Remove a resource from the apps state (DANGEROUS — orphans the GCP resource): make state-rm-gcp-workload ADDR='...' APP_ENV=dev
	@[ -n "$(ADDR)" ] || (echo "Error: ADDR is required. Usage: make state-rm-gcp-workload ADDR='module.host.resource.bar'" && exit 1)
	@echo "$(YELLOW)WARNING: Removing '$(ADDR)' from gcp-workload state (workspace: $(APP_WORKSPACE)) will ORPHAN this resource in GCP.$(NC)"
	@printf "Type 'yes' to confirm: " && read CONFIRM && [ "$$CONFIRM" = "yes" ] || (echo "Cancelled." && exit 1)
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp/workload state rm '$(ADDR)'

unlock-gcp-organization: ## Force-unlock a stuck Terraform lock on the gcp-organization workspace: make unlock-gcp-organization LOCK_ID=<id>
	@[ -n "$(LOCK_ID)" ] || (echo "Error: LOCK_ID is required. Usage: make unlock-gcp-organization LOCK_ID=<lock-id>" && exit 1)
	@$(TERRAFORM) -chdir=envs/gcp/organization force-unlock -force '$(LOCK_ID)'

unlock-gcp-workload: ## Force-unlock a stuck Terraform lock on a gcp-workload workspace: make unlock-gcp-workload LOCK_ID=<id> APP_ENV=dev
	@[ -n "$(LOCK_ID)" ] || (echo "Error: LOCK_ID is required. Usage: make unlock-gcp-workload LOCK_ID=<lock-id>" && exit 1)
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp/workload force-unlock -force '$(LOCK_ID)'

clean: ## Remove local Terraform caches (.terraform dirs, plan files, reports). Does NOT touch committed .terraform.lock.hcl files.
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.tfplan" -delete 2>/dev/null || true
	@rm -rf reports
	@echo "Cleaned .terraform dirs, plan files, and reports. Lock files (.terraform.lock.hcl) are version-controlled and were NOT deleted."

clean-locks: ## DANGER: Delete all .terraform.lock.hcl files so they can be regenerated. Only run this when intentionally refreshing provider lock files.
	@echo "$(YELLOW)WARNING: This deletes all committed .terraform.lock.hcl files from working tree.$(NC)"
	@echo "$(YELLOW)Re-generate with: terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64$(NC)"
	@printf "Type 'yes' to continue: " && read CONFIRM && [ "$$CONFIRM" = "yes" ] || (echo "Cancelled." && exit 1)
	@find . -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true

# ---------------------------------------------------------------------------
# Sandbox E2E: REAL apply + destroy against a disposable sandbox, never a
# landing-zone project/account. See docs/guides/sandbox-e2e.md.
# ---------------------------------------------------------------------------
.PHONY: e2e-gcp e2e-aws

# Simply-expanded (evaluated once) so the test and the cleanup see the same id.
ifndef E2E_RUN_ID
E2E_RUN_ID := $(shell date +%s)
endif
E2E_GCP_REGION ?= europe-west2
E2E_AWS_REGION ?= eu-west-2

e2e-gcp: ## REAL apply: run tests/e2e/gcp in a sandbox project, then label-scoped cleanup: make e2e-gcp E2E_GCP_PROJECT=<sandbox>
	@[ -n "$(E2E_GCP_PROJECT)" ] || (echo "Error: E2E_GCP_PROJECT (a disposable sandbox project) is required" && exit 1)
	@$(TERRAFORM) -chdir=tests/e2e/gcp init -input=false -lockfile=readonly >/dev/null
	@rc=0; \
	TF_VAR_project_id='$(E2E_GCP_PROJECT)' TF_VAR_region='$(E2E_GCP_REGION)' TF_VAR_run_id='$(E2E_RUN_ID)' \
		$(TERRAFORM) -chdir=tests/e2e/gcp test || rc=$$?; \
	./tests/e2e/scripts/cleanup-gcp.sh '$(E2E_GCP_PROJECT)' '$(E2E_GCP_REGION)' '$(E2E_RUN_ID)' || [ $$rc -ne 0 ] || rc=1; \
	exit $$rc

e2e-aws: ## REAL apply: run tests/e2e/aws in the ambient (sandbox!) AWS account, then tag-scoped cleanup: make e2e-aws E2E_AWS_REGION=eu-west-2
	@$(TERRAFORM) -chdir=tests/e2e/aws init -input=false -lockfile=readonly >/dev/null
	@rc=0; \
	TF_VAR_region='$(E2E_AWS_REGION)' TF_VAR_run_id='$(E2E_RUN_ID)' \
		$(TERRAFORM) -chdir=tests/e2e/aws test || rc=$$?; \
	./tests/e2e/scripts/cleanup-aws.sh '$(E2E_AWS_REGION)' '$(E2E_RUN_ID)' || [ $$rc -ne 0 ] || rc=1; \
	exit $$rc

# ---------------------------------------------------------------------------
# Single-source configuration (config/landing-zone.yaml)
# ---------------------------------------------------------------------------
.PHONY: init bootstrap-ids aws-preflight config-check scaffold-fixtures scaffold-fixtures-check

init: ## Scaffold config/landing-zone.yaml: make init ARGS="--org-name acme --clouds gcp,aws ..."
	@./scripts/init-landing-zone.sh $(ARGS)

bootstrap-ids: ## Write the tfc-admin workspace IDs for the local phase-0 gcp-bootstrap apply (gitignored)
	terraform -chdir=envs/tfc-admin output -raw gcp_bootstrap_tfvars > envs/gcp/bootstrap/tfc-workspaces.auto.tfvars

scaffold-fixtures: ## Regenerate tests/fixtures/scaffold/*.yaml from the scaffolder (one per cloud combination)
	./scripts/scaffold-fixtures.sh

scaffold-fixtures-check: ## Fail if tests/fixtures/scaffold/ differs from fresh scaffolder output (CI: meta-lint)
	./scripts/scaffold-fixtures.sh --check

config-check: ## Validate config/landing-zone.yaml (when present), the examples, config/sandbox/ and every test fixture and tests/fixtures/scaffold against config/landing-zone.schema.json (needs check-jsonschema)
	@./scripts/check-config.sh

aws-preflight: ## Check the AWS Organizations account quota fits config/landing-zone.yaml (needs the aws CLI and management-account credentials)
	@./scripts/aws-preflight.sh
