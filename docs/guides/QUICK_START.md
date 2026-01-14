# Quick Start Guide

Get up and running with Ashes DevOps Tools in 5 minutes!

## Prerequisites

- macOS, Linux, or WSL2 on Windows
- Git installed
- Internet connection
- (Optional) Docker for containerized development

---

## **5-Minute Setup**

### Step 1: Clone Repository (30 seconds)

```bash
git clone https://github.com/your-org/Ashes-Devops-Tools.git
cd Ashes-Devops-Tools
```

### Step 2: Install Dependencies (2 minutes)

```bash
# Install all required tools
make install
```

This installs:
- Terraform
- TFLint
- TFSec
- Checkov
- terraform-docs
- pre-commit

### Step 3: Install Pre-commit Hooks (30 seconds)

```bash
# Set up git hooks for code quality
make pre-commit-install
```

### Step 4: Verify Installation (1 minute)

```bash
# Check all tools are installed
make validate-requirements

# Run a quick validation
make ci
```

### Step 5: Start Developing! (1 minute)

```bash
# Initialize your environment
make init-dev

# Make changes to Terraform files
# ...

# Validate your changes
make fmt
make validate-all
make lint
make security
```

---

## **Verification Checklist**

After setup, verify everything works:

- [ ] `terraform version` shows >= 1.0.0
- [ ] `make help` shows all available commands
- [ ] `make ci` runs without errors
- [ ] Pre-commit hooks are installed (check `.git/hooks/`)
- [ ] `make fmt` formats code correctly

---

## **Next Steps**

### Learn the Workflow

1. **Read [Contributing Guide](../../CONTRIBUTING.md)** for detailed development workflow, testing, and module standards.
2. **Review [System Architecture](../architecture/ARCHITECTURE.md)** to understand the environment structure.

### Make Your First Change

1. Create a new branch:
   ```bash
   git checkout -b feature/my-first-change
   ```

2. Make changes to Terraform files

3. Run quality checks:
   ```bash
   make ci
   ```

4. Commit (pre-commit hooks will run automatically):
   ```bash
   git add .
   git commit -m "feat: add new feature"
   ```

5. Push and create PR:
   ```bash
   git push origin feature/my-first-change
   ```

---

## **Common Commands**

| Command | Description |
|:---|:---|
| `make help` | Show all available commands |
| `make fmt` | Format all Terraform files |
| `make validate-all` | Validate all modules |
| `make lint` | Run TFLint |
| `make security` | Run security scans |
| `make docs` | Generate module documentation |
| `make ci` | Run complete CI pipeline locally |
| `make plan-dev` | Plan dev environment changes |
| `make apply-dev` | Apply dev environment changes |

---

## **Troubleshooting**

### Installation Issues

**Problem**: `make install` fails

**Solution**:
```bash
# Install Homebrew first (macOS)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Or use package manager on Linux
sudo apt-get update  # Ubuntu/Debian
sudo yum update      # RHEL/CentOS
```

### Pre-commit Hook Issues

**Problem**: Pre-commit hooks fail

**Solution**:
```bash
# Update hooks
make pre-commit-update

# Run manually to see errors
make pre-commit-run
```

### Permission Issues

**Problem**: Permission denied errors

**Solution**:
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Fix Makefile permissions
chmod +x Makefile
```

---

## **Additional Resources**

- [Contributing Guide](../../CONTRIBUTING.md) - Development, Testing, and Deployment workflows
- [System Architecture](../architecture/ARCHITECTURE.md) - Design reference

---

## **Tips**

1. **Always run `make ci` before committing** to catch issues early
2. **Use `make help`** to discover available commands
3. **Read pre-commit output** if hooks fail
4. **Check [CONTRIBUTING.md](../../CONTRIBUTING.md)** for code standards

---

**Ready to contribute?** Check out [open issues](https://github.com/your-org/Ashes-Devops-Tools/issues) or create a new one!

