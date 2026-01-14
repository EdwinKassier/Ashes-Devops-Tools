# Troubleshooting Guide

Common issues and their solutions for the Ashes DevOps Tools repository.

---

## **General Troubleshooting**

### Enable Debug Mode

For detailed error messages:

```bash
# Terraform debug mode
export TF_LOG=DEBUG
terraform plan

# Makefile verbose mode
make -d <target>

# Pre-commit verbose mode
pre-commit run --all-files --verbose
```

---

## **Installation Issues**

### Issue: `make install` fails

**Symptoms**:
```text
Error: Command not found: brew
```

**Solutions**:

**macOS**:
```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Then retry
make install
```

**Linux (Ubuntu/Debian)**:
```bash
# Install prerequisites
sudo apt-get update
sudo apt-get install -y curl unzip

# Install tools individually
# Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# TFLint
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

# TFSec
brew install tfsec # or use binary release
```

### Issue: Tool version conflicts

**Symptoms**:
```text
Error: Required version constraint not met
```

**Solution**:
```bash
# Check versions
terraform version
tflint --version
tfsec --version

# Upgrade if needed
make upgrade-providers
```

---

## **Pre-commit Hook Issues**

### Issue: Pre-commit hooks fail on first run

**Symptoms**:
```text
[ERROR] Cowardly refusing to install hooks with `core.hooksPath` set
```

**Solution**:
```bash
# Remove existing hooks path
git config --unset core.hooksPath

# Reinstall hooks
make pre-commit-install
```

### Issue: terraform_docs fails

**Symptoms**:
```text
terraform-docs failed with exit code 1
```

**Solution**:
```bash
# Install terraform-docs
brew install terraform-docs

# Or download binary
curl -Lo ./terraform-docs.tar.gz https://github.com/terraform-docs/terraform-docs/releases/download/v0.16.0/terraform-docs-v0.16.0-$(uname)-amd64.tar.gz
tar -xzf terraform-docs.tar.gz
chmod +x terraform-docs
sudo mv terraform-docs /usr/local/bin/
```

### Issue: terraform_validate fails

**Symptoms**:
```text
Error: Required providers are not installed
```

**Solution**:
```bash
# Initialize all modules
for dir in modules/*/*/; do
  (cd "$dir" && terraform init -backend=false)
done

# Or use make command
make validate-all
```

### Issue: Hooks are too slow

**Symptoms**:
Pre-commit takes 5+ minutes

**Solution**:
```bash
# Skip slow hooks temporarily
SKIP=terraform_docs,terraform_tflint git commit -m "message"

# Or update hook configuration
pre-commit autoupdate
```

---

## **Terraform Issues**

### Issue: Terraform init fails

**Symptoms**:
```text
Error: Failed to query available provider packages
```

**Solutions**:

1. **Check internet connection**
2. **Clear terraform cache**:
   ```bash
   rm -rf .terraform
   rm .terraform.lock.hcl
   terraform init
   ```
3. **Check provider versions**:
   ```bash
   cat versions.tf
   # Ensure versions are valid
   ```

### Issue: Terraform plan fails with provider errors

**Symptoms**:
```text
Error: Provider configuration not present
```

**Solution**:
```bash
# Ensure you're in correct directory
cd envs/dev  # or envs/uat, envs/prod

# Initialize
terraform init

# Check providers
terraform providers
```

### Issue: State lock errors

**Symptoms**:
```text
Error: Error acquiring the state lock
```

**Solution**:
```bash
# Force unlock (use carefully!)
terraform force-unlock <LOCK_ID>

# Or wait for lock to release
# Check who has the lock in GCS bucket
```

### Issue: Module not found

**Symptoms**:
```text
Error: Module not installed
```

**Solution**:
```bash
# Initialize to download modules
terraform init

# If using local modules, check path
ls -la modules/host/  # Verify module exists

# Check module source in main.tf
```

---

## **Security Scan Issues**

### Issue: TFSec false positives

**Symptoms**:
```text
WARNING: Unencrypted storage bucket detected
```

**Solution**:

1. **Add exception to .tfsec.yml**:
   ```yaml
   exclude_checks:
     - google-storage-enable-ubla
   ```

2. **Or ignore inline**:
   ```hcl
   resource "google_storage_bucket" "bucket" {
     name = "my-bucket"
     #tfsec:ignore:google-storage-enable-ubla
   }
   ```

### Issue: Checkov fails with timeout

**Symptoms**:
```text
Error: Checkov scan timeout
```

**Solution**:
```bash
# Increase timeout in .tfsec.yml
timeout: 600  # 10 minutes

# Or skip specific checks
skip_check:
  - CKV_GCP_1
```

### Issue: Secret detected in code

**Symptoms**:
```text
Error: Detected private key in file
```

**Solution**:
```bash
# Remove secret from code
git rm --cached <file>

# Add to .gitignore
echo "<secret-file>" >> .gitignore

# Use environment variables instead
export TF_VAR_secret="value"
```

---

## **Documentation Issues**

### Issue: terraform-docs doesn't update README

**Symptoms**:
README.md not updated after running `make docs`

**Solution**:
```bash
# Check configuration
cat .terraform-docs.yml

# Run manually with verbose
terraform-docs markdown table --config .terraform-docs.yml modules/host/

# Ensure README.md exists
touch modules/host/README.md

# Check file permissions
chmod 644 modules/host/README.md
```

### Issue: Markdown linting fails

**Symptoms**:
```text
MD041: First line should be top level heading
```

**Solution**:
```bash
# Auto-fix markdown
markdownlint --fix **/*.md

# Or skip in pre-commit
SKIP=markdownlint git commit -m "message"
```

---

## **CI/CD Issues**

### Issue: GitHub Actions workflow fails

**Symptoms**:
Workflow fails on validate step

**Solutions**:

1. **Check workflow logs** in GitHub Actions tab

2. **Test locally**:
   ```bash
   # Run same commands as CI
   make fmt-check
   make validate-all
   make lint
   make security
   ```

3. **Check permissions**:
   ```yaml
   # In workflow file
   permissions:
     contents: read
     pull-requests: write
   ```

### Issue: Terraform apply workflow doesn't trigger

**Symptoms**:
Tagged commit doesn't trigger deployment

**Solution**:
```bash
# Check tag format
git tag -l  # Should be: env/dev/v1.0.0

# Create tag with correct format
git tag -a env/dev/v1.0.0 -m "Deploy dev v1.0.0"
git push origin env/dev/v1.0.0

# Check workflow file triggers
cat .github/workflows/terraform-apply.yml
```

### Issue: Authentication errors in GitHub Actions

**Symptoms**:
```text
Error: Failed to configure GCP credentials
```

**Solution**:
1. **Check secrets are set** in GitHub repository settings
2. **Verify Workload Identity is configured** in GCP
3. **Check service account has permissions**

---

## **Environment Issues**

### Issue: Wrong environment selected

**Symptoms**:
Changes applied to wrong environment

**Solution**:
```bash
# Always verify before applying
pwd  # Check you're in correct directory

# Use make commands which include environment in name
make plan-dev    # Clear which environment
make apply-prod  # Requires confirmation

# Check terraform workspace
terraform workspace show
```

### Issue: Environment variables not loaded

**Symptoms**:
```text
Error: Required variable not set
```

**Solution**:
```bash
# Check .env file exists
ls -la .env

# Source environment variables
source .env

# Or use terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars

# Or pass via command line
terraform plan -var="project_id=my-project"
```

---

## **Module Development Issues**

### Issue: Module validation fails

**Symptoms**:
```text
Error: Unsupported argument
```

**Solution**:
```bash
# Check Terraform version
terraform version  # Should be >= 1.0.0

# Check for typos in variables
cat variables.tf

# Validate syntax
terraform validate

# Check provider compatibility
cat versions.tf
```

### Issue: Module outputs not available

**Symptoms**:
```text
Error: Output value does not exist
```

**Solution**:
```bash
# Check outputs.tf exists
ls -la modules/host/outputs.tf

# Verify output is defined
cat modules/host/outputs.tf

# Apply changes first
terraform apply

# Then check outputs
terraform output
```

---

## **State Management Issues**

### Issue: State file conflicts

**Symptoms**:
```text
Error: Resource already exists
```

**Solution**:
```bash
# Import existing resource
terraform import google_storage_bucket.bucket my-bucket-name

# Or remove from state
terraform state rm google_storage_bucket.bucket

# Refresh state
terraform refresh
```

### Issue: State file is locked

**Symptoms**:
```text
Error: state lock already acquired
```

**Solution**:
```bash
# Wait for other process to finish
# Or force unlock (dangerous!)
terraform force-unlock <LOCK_ID>

# Check GCS bucket for lock info
gsutil ls gs://my-terraform-state-bucket/.terraform.lock.info
```

---

## **Performance Issues**

### Issue: `make ci` is too slow

**Symptoms**:
Takes 10+ minutes to run

**Solutions**:
```bash
# Run checks individually
make fmt-check     # Fast
make validate      # Medium
make lint          # Slow
make security      # Very slow

# Skip slow checks during development
make fmt
make validate

# Run full CI only before PR
make ci
```

### Issue: Terraform plan is slow

**Symptoms**:
Takes 5+ minutes

**Solutions**:
```bash
# Use -target for specific resources
terraform plan -target=module.host

# Refresh only when needed
terraform plan -refresh=false

# Use parallelism
terraform plan -parallelism=20
```

---

## **Getting Help**

If you can't resolve your issue:

1. **Check existing issues**: [GitHub Issues](https://github.com/your-org/Ashes-Devops-Tools/issues)
2. **Search documentation**: `grep -r "your-error" docs/`
3. **Ask for help**: Create a new issue with:
   - Error message
   - Steps to reproduce
   - Environment details (`terraform version`, OS, etc.)
   - What you've tried

4. **Security issues**: Email security@ashesproject.com (don't create public issue)

---

## **Additional Resources**

- [Terraform Debugging](https://www.terraform.io/docs/internals/debugging.html)
- [TFLint Rules](https://github.com/terraform-linters/tflint/tree/master/docs/rules)
- [TFSec Checks](https://aquasecurity.github.io/tfsec/)
- [GCP Troubleshooting](https://cloud.google.com/docs/troubleshooting)

---

**Last Updated**: January 2026

