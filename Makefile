.PHONY: help install fmt fmt-check validate validate-all lint security security-report docs docs-check test ci clean init-organization init-apps plan-organization plan-apps apply-organization apply-apps validate-requirements pre-commit-install pre-commit-run pre-commit-update

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
	@$(CHECKOV) -d modules --quiet --compact --framework terraform
	@$(CHECKOV) -d envs --quiet --compact --framework terraform

security-report: ## Generate detailed security reports
	@mkdir -p reports
	@$(TFSEC) . --config-file .tfsec.yml --exclude-path examples --format json > reports/tfsec-report.json
	@$(CHECKOV) -d modules --framework terraform --output json > reports/checkov-modules-report.json
	@$(CHECKOV) -d envs --framework terraform --output json > reports/checkov-envs-report.json

docs: ## Generate Terraform docs from repo root
	@bash scripts/module-docs.sh generate

docs-check: ## Verify Terraform docs are up to date
	@bash scripts/module-docs.sh check

test: ## Run terraform test suites when present
	@set -e; \
	test_dirs="$$(find envs modules -type f \( -name '*.tftest.hcl' -o -name '*.tftest.json' \) -exec dirname {} \; | sort -u)"; \
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

ci: ## Run the local CI pipeline
	@$(MAKE) fmt-check
	@$(MAKE) docs-check
	@$(MAKE) validate-all
	@$(MAKE) lint
	@$(MAKE) security
	@$(MAKE) test

init-organization: ## Initialize the organization root
	@$(TERRAFORM) -chdir=envs/organization init

init-apps: ## Initialize the apps root
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/apps init

plan-organization: ## Plan the organization root
	@$(TERRAFORM) -chdir=envs/organization plan

plan-apps: ## Plan the apps root for APP_ENV using APP_VARS
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/apps plan -var-file=$(APP_VARS)

apply-organization: ## Apply the organization root
	@$(TERRAFORM) -chdir=envs/organization apply

apply-apps: ## Apply the apps root for APP_ENV using APP_VARS
	@TF_WORKSPACE=$(APP_WORKSPACE) $(TERRAFORM) -chdir=envs/apps apply -var-file=$(APP_VARS)

validate-requirements: ## Print local tool versions
	@$(TERRAFORM) version
	@$(TFLINT) --version
	@$(TFSEC) --version
	@$(CHECKOV) --version
	@$(TERRAFORM_DOCS) --version

clean: ## Remove local Terraform caches and generated reports
	@find . -type d -name ".terraform" -prune -exec rm -rf {} +
	@find . -type f -name "*.tfplan" -delete
	@rm -rf reports
