# Security Policy

## 🔒 Overview

**Dot Sync** handles sensitive configuration files and cloud credentials. Security is paramount.

---

## 📋 Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

---

## 🚨 Reporting a Vulnerability

### Contact
- **Email:** kochj@digitalnoise.net
- **Subject:** [SECURITY] Dot Sync Vulnerability
- **Response Time:** Within 48 hours

### What to Include
- Clear description of the vulnerability
- Steps to reproduce
- Potential impact assessment
- Suggested fix (if available)

---

## 🛡️ Security Features

### Credential Protection
- ✅ **Automatic credential detection** - Scans for API keys, tokens, passwords
- ✅ **Pattern matching** - 10+ regex patterns for secret detection
- ✅ **Exclusion rules** - Never syncs SSH keys or credential files
- ✅ **Sanitization** - Removes auth sections from configs
- ✅ **Keychain storage** - Cloud credentials stored in macOS Keychain

### File Security
- ✅ **Checksum validation** - SHA-256 for integrity
- ✅ **Backup before overwrite** - Creates .backup files
- ✅ **Atomic writes** - All-or-nothing file operations
- ✅ **Permission preservation** - Maintains file permissions

### Network Security
- ✅ **HTTPS only** - All cloud operations over TLS
- ✅ **AWS Signature V4** - Signed requests to S3
- ✅ **OAuth 2.0** - For Azure and GCP
- ✅ **System credentials** - Uses system auth for iCloud

### Privacy
- ✅ **No telemetry** - No tracking or analytics
- ✅ **Local operation** - Works offline (except sync)
- ✅ **No third-party services** - Direct cloud provider communication

---

## 🔐 Files Never Synced

For security and privacy, these are automatically excluded:

### Credentials & Keys
- SSH private keys (id_rsa, id_dsa, id_ecdsa, id_ed25519)
- .aws/credentials
- .azure/credentials
- .docker/config.json (with auth tokens)
- .npmrc (with tokens)
- Any file containing detected credentials

### History & Cache
- .bash_history, .zsh_history
- .python_history
- .lesshst, .viminfo
- .cache/, .npm/, .gem/
- Any directory ending in "cache" or "Cache"

### System Files
- .DS_Store
- .CFUserTextEncoding
- .Trash/
- Temporary files (.swp, .tmp)

---

## 📚 Best Practices

### Before Syncing
1. Review file list - verify no sensitive files
2. Check security indicators (🔴 = unsafe)
3. Test on non-critical configs first
4. Backup important files manually

### For Developers
- Never commit actual credentials to code
- Use Keychain for cloud provider credentials
- Test security scanner with sample files
- Review logs for credential exposure

---

## 🔍 Security Audit

### Last Audit
- **Date:** December 11, 2025
- **Auditor:** Jordan Koch
- **Result:** Initial implementation with security best practices

### Security Checklist
- [x] Credential scanning implemented
- [x] Exclusion patterns comprehensive
- [x] Keychain storage for credentials
- [x] HTTPS enforced
- [x] Backup before overwrite
- [x] Pattern matching tested
- [ ] Full penetration testing (pending)
- [ ] Third-party security audit (planned)

---

**Last Updated:** December 11, 2025
**Security Policy Version:** 1.0
