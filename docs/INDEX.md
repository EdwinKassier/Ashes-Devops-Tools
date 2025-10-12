# 📚 Ashes DevOps Tools Documentation Index

## Quick Navigation

### 🚀 Getting Started
- **[Quick Start Guide](guides/QUICK_START.md)** - Get set up in 5 minutes
- **[Main README](../README.md)** - Project overview and architecture

### 📖 Guides
- **[Quick Start](guides/QUICK_START.md)** - 5-minute setup
- **[Troubleshooting](guides/TROUBLESHOOTING.md)** - Common issues and solutions

### 🏗️ Architecture
- **[System Architecture](architecture/ARCHITECTURE.md)** - Complete system design

### 🔒 Security
Security documentation includes comprehensive security scanning with TFSec, Checkov, Trivy, and GitLeaks. See the [Makefile](../Makefile) for security commands.

### 🤝 Contributing
Contributions are welcome! Please ensure all changes pass quality checks by running `make ci` before submitting.

### 📋 Development Tools
- **[Makefile](../Makefile)** - 40+ commands for development
- **[Pre-commit Configuration](../.pre-commit-config.yaml)** - Automated quality checks
- **[TFLint Configuration](../.tflint.hcl)** - Linting rules

---

## 📁 Documentation Structure

```
docs/
├── INDEX.md                     # This file - documentation navigation
├── architecture/
│   └── ARCHITECTURE.md          # Complete system architecture and design
└── guides/
    ├── QUICK_START.md          # 5-minute setup guide
    └── TROUBLESHOOTING.md      # Common issues and solutions
```

### **Root Configuration Files**
```
.
├── README.md                    # Main project documentation
├── Makefile                     # 40+ development commands
├── .pre-commit-config.yaml     # Automated quality checks (14 hooks)
├── .tflint.hcl                 # Terraform linting configuration
├── .terraform-docs.yml         # Documentation generation config
├── .editorconfig               # Editor configuration
└── .github/
    └── workflows/              # CI/CD automation
        ├── terraform-plan.yml
        ├── terraform-apply.yml
        ├── security-scan.yml
        └── documentation.yml
```

---

## 🎯 Common Tasks

### I want to...

**Get Started**
```bash
# See Quick Start Guide
make install && make pre-commit-install
```
→ [Quick Start Guide](guides/QUICK_START.md)

**Understand the System**
→ [System Architecture](architecture/ARCHITECTURE.md)

**Format and Validate Code**
```bash
make fmt && make validate-all
```

**Run Security Scans**
```bash
make security
```

**Fix an Issue**
→ [Troubleshooting Guide](guides/TROUBLESHOOTING.md)

**Deploy Changes**
```bash
make plan-dev    # Review changes
make apply-dev   # Apply to dev
```

**View All Commands**
```bash
make help
```

---

## 🔗 External Resources

- [Terraform Documentation](https://www.terraform.io/docs)
- [GCP Best Practices](https://cloud.google.com/docs/enterprise/best-practices-for-enterprise-organizations)
- [TFLint Rules](https://github.com/terraform-linters/tflint/tree/master/docs/rules)
- [TFSec Checks](https://aquasecurity.github.io/tfsec/)

---

**Infrastructure as Code for the Ashes Project**

