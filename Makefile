.PHONY: help install fmt fmt-check validate validate-all lint consistency security security-low security-report docs docs-check count count-check links shellcheck test ci clean clean-locks init-gcp-organization init-gcp-workload plan-gcp-organization plan-gcp-workload apply-gcp-organization apply-gcp-workload validate-requirements pre-commit-install pre-commit-run pre-commit-update state-list-gcp-organization state-list-gcp-workload state-rm-gcp-organization state-rm-gcp-workload unlock-gcp-organization unlock-gcp-workload

TERRAFORM := terraform
TFLINT := tflint
# Trivy replaces tfsec (EOL - Aqua folded it into Trivy). The version MUST match
# what reusable-security.yml runs (trivy-action `version:`), pinned in .tool-versions.
TRIVY := trivy
TRIVY_VERSION := $(shell awk '$$1=="trivy"{print $$2}' .tool-versions)
TRIVY_ARGS := config . --skip-dirs '**/.terraform'
SHELLCHECK_VERSION := $(shell awk '$$1=="shellcheck"{print $$2}' .tool-versions)
# Checkov MUST match the version CI runs (checkov-action pins the image; keep
# .tool-versions in sync). Newer checkov ships new checks, so a skewed local
# binary gives a false green. Prefer an exact-version uvx run; otherwise the
# local binary is used and `make security` refuses to run on a version mismatch.
CHECKOV_VERSION := $(shell awk '$$1=="checkov"{print $$2}' .tool-versions)
CHECKOV := $(shell if command -v uvx >/dev/null 2>&1; then echo "uvx --python 3.12 checkov==$(CHECKOV_VERSION)"; else echo checkov; fi)
TERRAFORM_DOCS := terraform-docs
PRE_COMMIT := pre-commit
ROOT_DISCOVERY := ./scripts/terraform-roots.sh

APP_ENV ?= dev
APP_WORKSPACE ?= gcp-workload-$(APP_ENV)
APP_VARS ?= examples/dev.tfvars

BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m

TERRAFORM_ROOTS := $(shell $(ROOT_DISCOVERY) all)

help: ## Show available commands
	@echo '$(BLUE)Ashes DevOps Tools$(NC)'
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make <target>\n"} /^[a-zA-Z0-9_.-]+:.*?##/ { printf "  $(BLUE)%-22s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

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

count: ## Print the live module/root/test-suite counts (the figures README.md and CLAUDE.md must quote)
	@./scripts/check-docs-counts.sh --print

count-check: ## Fail if README.md / CLAUDE.md counts drifted from the tree (CI: meta-lint)
	@./scripts/check-docs-counts.sh

links: ## Fail on broken repo-relative links in any Markdown file (offline; CI: meta-lint)
	@python3 scripts/check-md-links.py

shellcheck: ## Run shellcheck (pinned shellcheck-py, same as pre-commit) on scripts/*.sh and tests/e2e/scripts/*.sh
	@if command -v uvx >/dev/null 2>&1; then \
		uvx --from shellcheck-py==$(SHELLCHECK_VERSION).1 shellcheck --severity=warning scripts/*.sh tests/e2e/scripts/*.sh; \
	else \
		shellcheck --severity=warning scripts/*.sh tests/e2e/scripts/*.sh; \
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

consistency: ## Assert canonical strings (region regex, provider pins) haven't drifted across copies
	@./scripts/check-consistency.sh

ci: ## Run the local CI pipeline (fmt → consistency → counts → links → shellcheck → docs → validate → lint → test → security)
	@$(MAKE) fmt-check
	@$(MAKE) consistency
	@$(MAKE) count-check
	@$(MAKE) links
	@$(MAKE) shellcheck
	@$(MAKE) docs-check
	@$(MAKE) validate-all
	@$(MAKE) lint
	@$(MAKE) test
	@$(MAKE) security

init-gcp-organization: ## Initialize the gcp-organization root
	@$(TERRAFORM) -chdir=envs/gcp/organization init

init-gcp-workload: ## Initialize the gcp-workload root
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp/workload init

plan-gcp-organization: ## Plan the gcp-organization root
	@$(TERRAFORM) -chdir=envs/gcp/organization plan

plan-gcp-workload: ## Plan the gcp-workload root for APP_ENV using APP_VARS
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp/workload plan -var-file=$(abspath $(APP_VARS))

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
	@echo "$(YELLOW)Re-generate with: terraform providers lock -platform=linux_amd64 -platform=darwin_arm64$(NC)"
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
