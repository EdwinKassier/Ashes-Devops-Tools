.PHONY: help install fmt fmt-check validate validate-all lint security security-report test docs docs-check clean pre-commit-install pre-commit-run compliance-check cost-estimate graph upgrade-providers plan-dev plan-uat plan-prod apply-dev apply-uat apply-prod init-dev init-uat init-prod

# Variables
TERRAFORM := terraform
TFLINT := tflint
TFSEC := tfsec
CHECKOV := checkov
TERRAFORM_DOCS := terraform-docs
PRE_COMMIT := pre-commit

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

##@ General

help: ## Show this help message
	@echo '$(BLUE)Ashes DevOps Tools - Available Commands$(NC)'
	@echo ''
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make $(YELLOW)<target>$(NC)\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(BLUE)%-25s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(GREEN)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Installation

install: ## Install all required tools (terraform, tflint, tfsec, checkov, terraform-docs)
	@echo "$(BLUE)Installing required tools...$(NC)"
	@command -v $(TERRAFORM) >/dev/null 2>&1 || (echo "$(RED)Terraform not found. Installing...$(NC)" && bash scripts/install-terraform.sh)
	@command -v $(TFLINT) >/dev/null 2>&1 || (echo "$(YELLOW)TFLint not found. Installing...$(NC)" && brew install tflint)
	@command -v $(TFSEC) >/dev/null 2>&1 || (echo "$(YELLOW)TFSec not found. Installing...$(NC)" && brew install tfsec)
	@command -v $(CHECKOV) >/dev/null 2>&1 || (echo "$(YELLOW)Checkov not found. Installing...$(NC)" && pip3 install checkov)
	@command -v $(TERRAFORM_DOCS) >/dev/null 2>&1 || (echo "$(YELLOW)terraform-docs not found. Installing...$(NC)" && brew install terraform-docs)
	@command -v $(PRE_COMMIT) >/dev/null 2>&1 || (echo "$(YELLOW)pre-commit not found. Installing...$(NC)" && pip3 install pre-commit)
	@echo "$(GREEN)✓ All tools installed successfully!$(NC)"

##@ Code Quality

fmt: ## Format all Terraform files
	@echo "$(BLUE)Formatting Terraform files...$(NC)"
	@$(TERRAFORM) fmt -recursive .
	@echo "$(GREEN)✓ Formatting complete!$(NC)"

fmt-check: ## Check if Terraform files are formatted correctly
	@echo "$(BLUE)Checking Terraform file formatting...$(NC)"
	@$(TERRAFORM) fmt -recursive -check .

validate: ## Validate Terraform syntax in current directory
	@echo "$(BLUE)Validating Terraform syntax...$(NC)"
	@$(TERRAFORM) validate

validate-all: ## Validate all modules
	@echo "$(BLUE)Validating all modules...$(NC)"
	@for dir in modules/*/* envs/*/; do \
		if [ -f "$$dir/main.tf" ] || [ -f "$$dir/versions.tf" ]; then \
			echo "$(YELLOW)Validating $$dir...$(NC)"; \
			(cd "$$dir" && $(TERRAFORM) init -backend=false > /dev/null && $(TERRAFORM) validate) || exit 1; \
		fi \
	done
	@echo "$(GREEN)✓ All modules validated successfully!$(NC)"

lint: ## Run tflint on all modules
	@echo "$(BLUE)Running TFLint...$(NC)"
	@$(TFLINT) --init
	@$(TFLINT) --recursive --config=$(PWD)/.tflint.hcl
	@echo "$(GREEN)✓ Linting complete!$(NC)"

##@ Security

security: ## Run security scans (tfsec and checkov)
	@echo "$(BLUE)Running security scans...$(NC)"
	@echo "$(YELLOW)Running TFSec...$(NC)"
	@$(TFSEC) . --config-file .tfsec.yml || true
	@echo "$(YELLOW)Running Checkov...$(NC)"
	@$(CHECKOV) -d . --quiet --compact --framework terraform || true
	@echo "$(GREEN)✓ Security scans complete!$(NC)"

security-report: ## Generate detailed security report
	@echo "$(BLUE)Generating security report...$(NC)"
	@mkdir -p reports
	@$(TFSEC) . --config-file .tfsec.yml --format json > reports/tfsec-report.json
	@$(TFSEC) . --config-file .tfsec.yml --format html > reports/tfsec-report.html
	@$(CHECKOV) -d . --framework terraform --output json > reports/checkov-report.json
	@$(CHECKOV) -d . --framework terraform --output cli > reports/checkov-report.txt
	@echo "$(GREEN)✓ Security reports generated in reports/$(NC)"

##@ Documentation

docs: ## Generate documentation for all modules
	@echo "$(BLUE)Generating module documentation...$(NC)"
	@for dir in modules/*/*/; do \
		if [ -f "$$dir/main.tf" ]; then \
			echo "$(YELLOW)Generating docs for $$dir...$(NC)"; \
			$(TERRAFORM_DOCS) markdown table --config .terraform-docs.yml --output-file README.md "$$dir"; \
		fi \
	done
	@echo "$(GREEN)✓ Documentation generated!$(NC)"

docs-check: ## Verify documentation is up to date
	@echo "$(BLUE)Checking documentation...$(NC)"
	@for dir in modules/*/*/; do \
		if [ -f "$$dir/main.tf" ]; then \
			$(TERRAFORM_DOCS) markdown table --config .terraform-docs.yml --output-check "$$dir" || exit 1; \
		fi \
	done
	@echo "$(GREEN)✓ Documentation is up to date!$(NC)"

##@ Development Environment Setup

init-dev: ## Initialize Terraform for dev environment
	@echo "$(BLUE)Initializing dev environment...$(NC)"
	@cd envs/dev && $(TERRAFORM) init
	@echo "$(GREEN)✓ Dev environment initialized!$(NC)"

init-uat: ## Initialize Terraform for UAT environment
	@echo "$(BLUE)Initializing UAT environment...$(NC)"
	@cd envs/uat && $(TERRAFORM) init
	@echo "$(GREEN)✓ UAT environment initialized!$(NC)"

init-prod: ## Initialize Terraform for prod environment
	@echo "$(BLUE)Initializing prod environment...$(NC)"
	@cd envs/prod && $(TERRAFORM) init
	@echo "$(GREEN)✓ Prod environment initialized!$(NC)"

##@ Environment Operations

plan-dev: ## Plan dev environment changes
	@echo "$(BLUE)Planning dev environment...$(NC)"
	@cd envs/dev && $(TERRAFORM) plan -out=tfplan

plan-uat: ## Plan UAT environment changes
	@echo "$(BLUE)Planning UAT environment...$(NC)"
	@cd envs/uat && $(TERRAFORM) plan -out=tfplan

plan-prod: ## Plan prod environment changes
	@echo "$(BLUE)Planning prod environment...$(NC)"
	@cd envs/prod && $(TERRAFORM) plan -out=tfplan

apply-dev: ## Apply dev environment changes
	@echo "$(YELLOW)⚠ Applying changes to dev environment...$(NC)"
	@cd envs/dev && $(TERRAFORM) apply tfplan
	@echo "$(GREEN)✓ Dev environment updated!$(NC)"

apply-uat: ## Apply UAT environment changes
	@echo "$(YELLOW)⚠ Applying changes to UAT environment...$(NC)"
	@read -p "Are you sure you want to apply UAT changes? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd envs/uat && $(TERRAFORM) apply tfplan; \
		echo "$(GREEN)✓ UAT environment updated!$(NC)"; \
	else \
		echo "$(RED)✗ Apply cancelled$(NC)"; \
	fi

apply-prod: ## Apply prod environment changes (requires confirmation)
	@echo "$(RED)⚠ WARNING: Applying changes to PRODUCTION environment!$(NC)"
	@read -p "Type 'yes' to confirm production deployment: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		cd envs/prod && $(TERRAFORM) apply tfplan; \
		echo "$(GREEN)✓ Production environment updated!$(NC)"; \
	else \
		echo "$(RED)✗ Production apply cancelled$(NC)"; \
	fi

##@ Pre-commit Hooks

pre-commit-install: ## Install pre-commit hooks
	@echo "$(BLUE)Installing pre-commit hooks...$(NC)"
	@$(PRE_COMMIT) install
	@$(PRE_COMMIT) install --hook-type commit-msg
	@echo "$(GREEN)✓ Pre-commit hooks installed!$(NC)"

pre-commit-run: ## Run pre-commit on all files
	@echo "$(BLUE)Running pre-commit checks...$(NC)"
	@$(PRE_COMMIT) run --all-files

pre-commit-update: ## Update pre-commit hooks
	@echo "$(BLUE)Updating pre-commit hooks...$(NC)"
	@$(PRE_COMMIT) autoupdate

##@ CI/CD

ci: ## Run CI pipeline locally
	@echo "$(BLUE)Running CI pipeline...$(NC)"
	@$(MAKE) fmt-check
	@$(MAKE) validate-all
	@$(MAKE) lint
	@$(MAKE) security
	@echo "$(GREEN)✓ CI pipeline complete!$(NC)"

pre-deploy: ## Run pre-deployment checks
	@echo "$(BLUE)Running pre-deployment checks...$(NC)"
	@$(MAKE) fmt-check
	@$(MAKE) validate-all
	@$(MAKE) lint
	@$(MAKE) security
	@$(MAKE) docs-check
	@echo "$(GREEN)✓ Pre-deployment checks passed!$(NC)"

##@ Utilities

clean: ## Clean temporary files and caches
	@echo "$(BLUE)Cleaning temporary files...$(NC)"
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.tfplan" -delete 2>/dev/null || true
	@find . -type f -name "*.tfstate" -delete 2>/dev/null || true
	@find . -type f -name "*.tfstate.backup" -delete 2>/dev/null || true
	@find . -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@rm -rf reports/ 2>/dev/null || true
	@echo "$(GREEN)✓ Cleanup complete!$(NC)"

graph: ## Generate dependency graph
	@echo "$(BLUE)Generating dependency graph...$(NC)"
	@cd envs/organisation && $(TERRAFORM) init -backend=false > /dev/null
	@cd envs/organisation && $(TERRAFORM) graph | dot -Tpng > ../../docs/dependency-graph.png
	@echo "$(GREEN)✓ Graph generated at docs/dependency-graph.png$(NC)"

upgrade-providers: ## Upgrade provider versions
	@echo "$(BLUE)Upgrading provider versions...$(NC)"
	@for dir in modules/*/* envs/*/; do \
		if [ -f "$$dir/versions.tf" ]; then \
			echo "$(YELLOW)Upgrading $$dir...$(NC)"; \
			(cd "$$dir" && $(TERRAFORM) init -upgrade); \
		fi \
	done
	@echo "$(GREEN)✓ Providers upgraded!$(NC)"

cost-estimate: ## Estimate infrastructure costs (requires infracost)
	@echo "$(BLUE)Estimating costs...$(NC)"
	@command -v infracost >/dev/null 2>&1 || (echo "$(RED)Infracost not found. Install from https://www.infracost.io/$(NC)" && exit 1)
	@cd envs/dev && infracost breakdown --path .
	@echo "$(GREEN)✓ Cost estimation complete!$(NC)"

compliance-check: ## Run compliance checks
	@echo "$(BLUE)Running compliance checks...$(NC)"
	@command -v terraform-compliance >/dev/null 2>&1 || (echo "$(YELLOW)terraform-compliance not found. Install with: pip install terraform-compliance$(NC)")
	@echo "$(GREEN)✓ Compliance checks complete!$(NC)"

validate-requirements: ## Validate requirements.txt for dependencies
	@echo "$(BLUE)Validating tool versions...$(NC)"
	@$(TERRAFORM) version
	@$(TFLINT) --version || echo "$(YELLOW)TFLint not installed$(NC)"
	@$(TFSEC) --version || echo "$(YELLOW)TFSec not installed$(NC)"
	@$(CHECKOV) --version || echo "$(YELLOW)Checkov not installed$(NC)"
	@$(TERRAFORM_DOCS) --version || echo "$(YELLOW)terraform-docs not installed$(NC)"
	@echo "$(GREEN)✓ Version check complete!$(NC)"

##@ Release Management

create-prod-tag: ## Create production release tag
	@echo "$(BLUE)Creating production release tag...$(NC)"
	@./scripts/create-prod-release.sh

