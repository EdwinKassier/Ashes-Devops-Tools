.PHONY: help install fmt fmt-check validate validate-all lint security security-report docs docs-check test ci clean clean-locks init-organization init-apps plan-organization plan-apps apply-organization apply-apps validate-requirements pre-commit-install pre-commit-run pre-commit-update state-list-organization state-list-apps state-rm-organization state-rm-apps unlock-organization unlock-apps

TERRAFORM := terraform
TFLINT := tflint
TFSEC := tfsec
CHECKOV := checkov
TERRAFORM_DOCS := terraform-docs
PRE_COMMIT := pre-commit
ROOT_DISCOVERY := ./scripts/terraform-roots.sh

APP_ENV ?= dev
APP_WORKSPACE ?= apps-$(APP_ENV)
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
		$(TERRAFORM) -chdir=$$dir init -backend=false -input=false >/dev/null; \
		$(TERRAFORM) -chdir=$$dir validate; \
	done

lint: ## Run TFLint across the repository
	@$(TFLINT) --init
	@set -e; \
	for dir in $(TERRAFORM_ROOTS); do \
		echo "$(YELLOW)Linting $$dir$(NC)"; \
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
		$(TERRAFORM) -chdir=$$dir init -backend=false -input=false >/dev/null; \
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

init-organization: ## Initialize the organization root
	@$(TERRAFORM) -chdir=envs/organization init

init-apps: ## Initialize the apps root
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/apps init

plan-organization: ## Plan the organization root
	@$(TERRAFORM) -chdir=envs/organization plan

plan-apps: ## Plan the apps root for APP_ENV using APP_VARS
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/apps plan -var-file=$(APP_VARS)

apply-organization: ## Apply the organization root (interactive confirmation required)
	@echo "$(YELLOW)WARNING: You are about to apply changes to the ORGANIZATION root (folders, projects, org policies, hub network).$(NC)"
	@echo "$(YELLOW)This affects all environments. Review the plan first with: make plan-organization$(NC)"
	@printf "Type 'yes' to continue: " && read CONFIRM && [ "$$CONFIRM" = "yes" ] || (echo "Cancelled." && exit 1)
	@$(TERRAFORM) -chdir=envs/organization apply

apply-apps: ## Apply the apps root for APP_ENV using APP_VARS (interactive confirmation required)
	@echo "$(YELLOW)WARNING: You are about to apply changes to the APPS root for environment: $(APP_ENV)$(NC)"
	@echo "$(YELLOW)Review the plan first with: make plan-apps APP_ENV=$(APP_ENV) APP_VARS=$(APP_VARS)$(NC)"
	@printf "Type 'yes' to continue: " && read CONFIRM && [ "$$CONFIRM" = "yes" ] || (echo "Cancelled." && exit 1)
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/apps apply -var-file=$(APP_VARS)

validate-requirements: ## Print local tool versions
	@$(TERRAFORM) version
	@$(TFLINT) --version
	@$(TFSEC) --version
	@$(CHECKOV) --version
	@$(TERRAFORM_DOCS) --version

state-list-organization: ## List resources in the organization workspace state
	@$(TERRAFORM) -chdir=envs/organization state list

state-list-apps: ## List resources in the apps workspace state (APP_ENV=dev)
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/apps state list

state-rm-organization: ## Remove a resource from the organization state (DANGEROUS — orphans the GCP resource): make state-rm-organization ADDR='module.foo.resource.bar'
	@[ -n "$(ADDR)" ] || (echo "Error: ADDR is required. Usage: make state-rm-organization ADDR='module.foo.resource.bar'" && exit 1)
	@echo "$(YELLOW)WARNING: Removing '$(ADDR)' from state will ORPHAN this resource in GCP.$(NC)"
	@echo "$(YELLOW)The resource will continue to exist but Terraform will no longer manage it.$(NC)"
	@printf "Type 'yes' to confirm: " && read CONFIRM && [ "$$CONFIRM" = "yes" ] || (echo "Cancelled." && exit 1)
	@$(TERRAFORM) -chdir=envs/organization state rm '$(ADDR)'

state-rm-apps: ## Remove a resource from the apps state (DANGEROUS — orphans the GCP resource): make state-rm-apps ADDR='...' APP_ENV=dev
	@[ -n "$(ADDR)" ] || (echo "Error: ADDR is required. Usage: make state-rm-apps ADDR='module.host.resource.bar'" && exit 1)
	@echo "$(YELLOW)WARNING: Removing '$(ADDR)' from apps state (workspace: $(APP_WORKSPACE)) will ORPHAN this resource in GCP.$(NC)"
	@printf "Type 'yes' to confirm: " && read CONFIRM && [ "$$CONFIRM" = "yes" ] || (echo "Cancelled." && exit 1)
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/apps state rm '$(ADDR)'

unlock-organization: ## Force-unlock a stuck Terraform lock on the organization workspace: make unlock-organization LOCK_ID=<id>
	@[ -n "$(LOCK_ID)" ] || (echo "Error: LOCK_ID is required. Usage: make unlock-organization LOCK_ID=<lock-id>" && exit 1)
	@$(TERRAFORM) -chdir=envs/organization force-unlock -force '$(LOCK_ID)'

unlock-apps: ## Force-unlock a stuck Terraform lock on an apps workspace: make unlock-apps LOCK_ID=<id> APP_ENV=dev
	@[ -n "$(LOCK_ID)" ] || (echo "Error: LOCK_ID is required. Usage: make unlock-apps LOCK_ID=<lock-id>" && exit 1)
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/apps force-unlock -force '$(LOCK_ID)'

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
