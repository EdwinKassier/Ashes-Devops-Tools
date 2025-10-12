# Pull Request

## Description

<!-- Provide a brief description of the changes in this PR -->

## Type of Change

<!-- Mark the relevant option with an "x" -->

- [ ] 🐛 Bug fix (non-breaking change which fixes an issue)
- [ ] ✨ New feature (non-breaking change which adds functionality)
- [ ] 💥 Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] 📝 Documentation update
- [ ] 🎨 Code style update (formatting, renaming)
- [ ] ♻️ Code refactoring (no functional changes)
- [ ] ⚡ Performance improvement
- [ ] ✅ Test update
- [ ] 🔧 Configuration change
- [ ] 🏗️ Infrastructure change

## Environment

<!-- Mark the environments affected by this change -->

- [ ] 🏢 Organization
- [ ] 🔧 Development
- [ ] 🧪 UAT
- [ ] 🚀 Production

## Changes Made

<!-- List the specific changes made in this PR -->

- 
- 
- 

## Related Issues

<!-- Link to related issues using keywords: Fixes #123, Closes #456, Related to #789 -->

Fixes #
Related to #

## Testing

<!-- Describe the tests you ran to verify your changes -->

### Test Commands Run

```bash
make fmt-check
make validate-all
make lint
make security
```

### Test Results

- [ ] ✅ Terraform format check passed
- [ ] ✅ Terraform validation passed
- [ ] ✅ TFLint passed
- [ ] ✅ TFSec security scan passed
- [ ] ✅ Checkov security scan passed
- [ ] ✅ Manual testing completed

### Test Environment

- **Environment**: Dev/UAT/Prod
- **Terraform Version**: 
- **Provider Version**: 

## Documentation

<!-- Check all that apply -->

- [ ] 📖 Module README updated (or auto-generated with terraform-docs)
- [ ] 📄 Main README updated (if applicable)
- [ ] 📋 CHANGELOG updated
- [ ] 💬 Code comments added for complex logic
- [ ] 🔒 Security considerations documented

## Security Checklist

<!-- Verify all security requirements -->

- [ ] 🔐 No secrets or credentials committed
- [ ] 🔒 Sensitive variables marked as `sensitive = true`
- [ ] 👤 IAM follows least privilege principle
- [ ] 🔑 Encryption enabled where applicable
- [ ] 📊 Audit logging configured
- [ ] 🛡️ Security scans passed
- [ ] 🚫 No public access to resources (unless intentional and documented)

## Pre-merge Checklist

<!-- Verify before merging -->

- [ ] ✅ Self-review completed
- [ ] 📝 Code follows project style guidelines
- [ ] 🧪 All tests pass
- [ ] 📚 Documentation updated
- [ ] 🔍 No new linting warnings
- [ ] 🔒 Security scans pass
- [ ] 💬 Code has appropriate comments
- [ ] ⚙️ CI/CD pipeline passes
- [ ] 👀 Reviewed by at least one team member
- [ ] 🔗 Related PRs/dependencies merged

## Screenshots/Outputs

<!-- If applicable, add screenshots or terraform plan outputs -->

<details>
<summary>Terraform Plan Output (if applicable)</summary>

```terraform
# Paste terraform plan output here

```

</details>

## Breaking Changes

<!-- If this is a breaking change, describe the impact and migration path -->

**Impact**:

**Migration Steps**:
1. 
2. 
3. 

## Rollback Plan

<!-- Describe how to rollback if issues are found after deployment -->

1. 
2. 
3. 

## Additional Notes

<!-- Any additional information that reviewers should know -->

---

## Reviewer Checklist

<!-- For reviewers -->

- [ ] Code follows project standards
- [ ] Security considerations addressed
- [ ] Documentation is sufficient
- [ ] Tests are appropriate
- [ ] No obvious issues or bugs
- [ ] Breaking changes properly documented
- [ ] Rollback plan is clear

---

**Note**: Delete any sections that are not applicable to your PR.

