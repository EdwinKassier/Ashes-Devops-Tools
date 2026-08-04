.PHONY: help install fmt fmt-check validate validate-all lint security security-report docs docs-check count test ci clean clean-locks init-gcp-organization init-gcp-workload plan-gcp-organization plan-gcp-workload apply-gcp-organization apply-gcp-workload validate-requirements pre-commit-install pre-commit-run pre-commit-update state-list-gcp-organization state-list-gcp-workload state-rm-gcp-organization state-rm-gcp-workload unlock-gcp-organization unlock-gcp-workload

TERRAFORM := terraform
TFLINT := tflint
TFSEC := tfsec
CHECKOV := checkov
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
		$(TERRAFORM) -chdir=$$dir validate; \
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

security: ## Run tfsec and checkov and fail on real findings
	@$(TFSEC) . --config-file .tfsec.yml --exclude-path examples
	@$(CHECKOV) -d modules --quiet --compact --framework terraform --config-file .checkov.yaml
	@$(CHECKOV) -d envs --quiet --compact --framework terraform --config-file .checkov.yaml

security-report: ## Generate detailed security reports
	@mkdir -p reports
	@$(TFSEC) . --config-file .tfsec.yml --exclude-path examples --format json > reports/tfsec-report.json
	@$(CHECKOV) -d modules --framework terraform --output json --config-file .checkov.yaml > reports/checkov-modules-report.json
	@$(CHECKOV) -d envs --framework terraform --output json --config-file .checkov.yaml > reports/checkov-envs-report.json

docs: ## Generate Terraform docs from repo root
	@bash scripts/module-docs.sh generate

docs-check: ## Verify Terraform docs are up to date
	@bash scripts/module-docs.sh check

count: ## Recompute the hand-maintained module/root/test counts in CLAUDE.md and README.md
	@echo "modules:         $$(find modules -name main.tf -not -path '*/examples/*' -not -path '*/.terraform/*' | wc -l | tr -d ' ')"
	@echo "deployable roots: $$(find envs -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
	@echo "test suites:     $$(find modules envs -name '*.tftest.hcl' -not -path '*/.terraform/*' | wc -l | tr -d ' ')"

test: ## Run terraform test suites (searches module roots and their tests/ subdirs)
	@set -e; \
	test_dirs="$$(find envs modules -type f \( -name '*.tftest.hcl' -o -name '*.tftest.json' \) \
	  | xargs -I{} dirname {} \
	  | sed 's|/tests$$||' \
	  | sort -u)"; \
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

ci: ## Run the local CI pipeline (fmt → docs → validate → lint → test → security)
	@$(MAKE) fmt-check
	@$(MAKE) docs-check
	@$(MAKE) validate-all
	@$(MAKE) lint
	@$(MAKE) test
	@$(MAKE) security

init-gcp-organization: ## Initialize the gcp-organization root
	@$(TERRAFORM) -chdir=envs/gcp-organization init

init-gcp-workload: ## Initialize the gcp-workload root
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp-workload init

plan-gcp-organization: ## Plan the gcp-organization root
	@$(TERRAFORM) -chdir=envs/gcp-organization plan

plan-gcp-workload: ## Plan the gcp-workload root for APP_ENV using APP_VARS
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp-workload plan -var-file=$(abspath $(APP_VARS))

apply-gcp-organization: ## Apply the gcp-organization root (interactive confirmation required)
	@echo "$(YELLOW)WARNING: You are about to apply changes to the GCP-ORGANIZATION root (folders, projects, org policies, hub network).$(NC)"
	@echo "$(YELLOW)This affects all environments. Review the plan first with: make plan-gcp-organization$(NC)"
	@printf "Type 'yes' to continue: " && read CONFIRM && [ "$$CONFIRM" = "yes" ] || (echo "Cancelled." && exit 1)
	@$(TERRAFORM) -chdir=envs/gcp-organization apply

apply-gcp-workload: ## Apply the gcp-workload root for APP_ENV using APP_VARS (interactive confirmation required)
	@echo "$(YELLOW)WARNING: You are about to apply changes to the GCP-WORKLOAD root for environment: $(APP_ENV)$(NC)"
	@echo "$(YELLOW)Review the plan first with: make plan-gcp-workload APP_ENV=$(APP_ENV) APP_VARS=$(APP_VARS)$(NC)"
	@printf "Type 'yes' to continue: " && read CONFIRM && [ "$$CONFIRM" = "yes" ] || (echo "Cancelled." && exit 1)
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp-workload apply -var-file=$(abspath $(APP_VARS))

validate-requirements: ## Print local tool versions
	@$(TERRAFORM) version
	@$(TFLINT) --version
	@$(TFSEC) --version
	@$(CHECKOV) --version
	@$(TERRAFORM_DOCS) --version

state-list-gcp-organization: ## List resources in the gcp-organization workspace state
	@$(TERRAFORM) -chdir=envs/gcp-organization state list

state-list-gcp-workload: ## List resources in the gcp-workload workspace state (APP_ENV=dev)
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp-workload state list

state-rm-gcp-organization: ## Remove a resource from the gcp-organization state (DANGEROUS — orphans the GCP resource): make state-rm-gcp-organization ADDR='module.foo.resource.bar'
	@[ -n "$(ADDR)" ] || (echo "Error: ADDR is required. Usage: make state-rm-gcp-organization ADDR='module.foo.resource.bar'" && exit 1)
	@echo "$(YELLOW)WARNING: Removing '$(ADDR)' from state will ORPHAN this resource in GCP.$(NC)"
	@echo "$(YELLOW)The resource will continue to exist but Terraform will no longer manage it.$(NC)"
	@printf "Type 'yes' to confirm: " && read CONFIRM && [ "$$CONFIRM" = "yes" ] || (echo "Cancelled." && exit 1)
	@$(TERRAFORM) -chdir=envs/gcp-organization state rm '$(ADDR)'

state-rm-gcp-workload: ## Remove a resource from the apps state (DANGEROUS — orphans the GCP resource): make state-rm-gcp-workload ADDR='...' APP_ENV=dev
	@[ -n "$(ADDR)" ] || (echo "Error: ADDR is required. Usage: make state-rm-gcp-workload ADDR='module.host.resource.bar'" && exit 1)
	@echo "$(YELLOW)WARNING: Removing '$(ADDR)' from gcp-workload state (workspace: $(APP_WORKSPACE)) will ORPHAN this resource in GCP.$(NC)"
	@printf "Type 'yes' to confirm: " && read CONFIRM && [ "$$CONFIRM" = "yes" ] || (echo "Cancelled." && exit 1)
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp-workload state rm '$(ADDR)'

unlock-gcp-organization: ## Force-unlock a stuck Terraform lock on the gcp-organization workspace: make unlock-gcp-organization LOCK_ID=<id>
	@[ -n "$(LOCK_ID)" ] || (echo "Error: LOCK_ID is required. Usage: make unlock-gcp-organization LOCK_ID=<lock-id>" && exit 1)
	@$(TERRAFORM) -chdir=envs/gcp-organization force-unlock -force '$(LOCK_ID)'

unlock-gcp-workload: ## Force-unlock a stuck Terraform lock on a gcp-workload workspace: make unlock-gcp-workload LOCK_ID=<id> APP_ENV=dev
	@[ -n "$(LOCK_ID)" ] || (echo "Error: LOCK_ID is required. Usage: make unlock-gcp-workload LOCK_ID=<lock-id>" && exit 1)
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/gcp-workload force-unlock -force '$(LOCK_ID)'

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
