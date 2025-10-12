---
name: Security Issue
about: Report a security concern (non-critical)
title: '[SECURITY] '
labels: security
assignees: ''
---

## ⚠️ IMPORTANT SECURITY NOTICE

**If this is a critical security vulnerability, DO NOT create a public issue.**

Please email security concerns to: **security@ashesproject.com**

---

## Security Concern Description

<!-- Describe the security concern (for non-critical issues only) -->

## Type of Security Issue

- [ ] Configuration weakness
- [ ] Missing security control
- [ ] Overly permissive IAM
- [ ] Unencrypted resource
- [ ] Missing audit logging
- [ ] Exposed resource
- [ ] Dependency vulnerability
- [ ] Other: 

## Affected Components

**Module/Resource:**
<!-- Which module or resource is affected? -->

**Environment:**
- [ ] Development
- [ ] UAT
- [ ] Production
- [ ] All environments

## Current Configuration

<!-- Show the current insecure configuration (remove sensitive data) -->

```hcl
# Current configuration
```

## Security Risk

**Severity:**
- [ ] High
- [ ] Medium
- [ ] Low
- [ ] Informational

**Potential Impact:**
<!-- What could happen if this is exploited? -->

## Recommended Solution

<!-- How should this be fixed? -->

```hcl
# Recommended secure configuration
```

## Compliance Impact

<!-- Does this affect compliance with any standards? -->

- [ ] ISO 27001
- [ ] ISO 22301
- [ ] GCP Security Best Practices
- [ ] Other: 

## Detection Method

<!-- How was this security issue discovered? -->

- [ ] TFSec scan
- [ ] Checkov scan
- [ ] Manual review
- [ ] Security audit
- [ ] Other: 

## References

<!-- Link to relevant security documentation or guidelines -->

- 
- 

## Additional Context

<!-- Any other relevant information -->

---

**For critical vulnerabilities, email security@ashesproject.com instead of creating a public issue.**

