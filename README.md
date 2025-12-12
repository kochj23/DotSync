# Dot Sync

![Platform](https://img.shields.io/badge/platform-macOS%2013.0%2B-lightgrey)
![Swift](https://img.shields.io/badge/swift-5.0-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

> Smart dotfiles synchronization across machines using cloud storage

---

## Overview

**Dot Sync** is a macOS application for syncing configuration files (dotfiles) across multiple machines using cloud storage. Unlike iCloud which handles Documents and Desktop, Dot Sync focuses on developer configuration files that iCloud doesn't touch.

### What It Syncs

Think of it as version control for your dotfiles with conflict detection:
- Shell configs (.zshrc, .bashrc, .bash_profile)
- **Terminal profiles** (~/Library/Preferences/com.apple.Terminal.plist) - **NEW!**
- **iTerm2 profiles** (~/Library/Preferences/com.googlecode.iterm2.plist) - **NEW!**
- Git configuration (.gitconfig)
- Editor configs (.vimrc, .vim/, VS Code settings)
- Cloud CLI configs (.aws/config, .azure/config, gcloud/)
- Docker settings (.docker/config.json)
- Claude Code settings (.claude/CLAUDE.md, .claude/settings.json)
- Custom tool configs (oh-my-zsh/custom/, .config/*)

### What It DOESN'T Sync (Security)

- SSH private keys (id_rsa, id_ed25519)
- Credential files (.aws/credentials, .docker with auth tokens)
- Command history (.bash_history, .zsh_history)
- Cache directories (.cache/, .npm/)
- Binary files and models

---

## Features

### Core Functionality
- ✅ **Automatic Discovery** - Scans home directory for config files
- ✅ **Smart Categorization** - Groups by type (shell, git, editor, cloud)
- ✅ **Priority Ranking** - Critical, high, medium, low
- ✅ **Security Scanning** - Detects and excludes files with credentials
- ✅ **Conflict Detection** - Compares local vs remote timestamps
- ✅ **Bidirectional Sync** - Upload or download as needed

### Cloud Storage Support
- ✅ AWS S3
- ✅ Azure Blob Storage
- ✅ Google Cloud Storage
- ✅ iCloud Drive
- ✅ S3-Compatible (MinIO, DigitalOcean Spaces, Wasabi)

### Security Features
- ✅ **Credential Scanning** - Automatic detection of API keys, tokens, passwords
- ✅ **Secure Exclusion** - Never syncs SSH keys or credential files
- ✅ **Pattern Matching** - Regex-based secret detection
- ✅ **Backup Before Sync** - Creates .backup files before overwriting
- ✅ **Encrypted Storage** - Optional encryption for cloud data

### User Experience
- ✅ **Native SwiftUI Interface** - Modern macOS design
- ✅ **File Browser** - Categorized tree view
- ✅ **Sync Status Indicators** - Visual state for each file
- ✅ **Conflict Resolution** - Side-by-side diff (coming soon)
- ✅ **Progress Tracking** - Real-time sync progress
- ✅ **Audit Log** - History of all sync operations

---

## Installation

### Requirements

- **macOS 13.0 (Ventura) or later**
- **Xcode 15.0+** (for building from source)
- **Cloud storage account** (AWS, Azure, GCP, or iCloud)

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/kochj23/DotSync.git
cd DotSync
```

2. Open in Xcode:
```bash
open "Dot Sync.xcodeproj"
```

3. Build and run:
   - Press ⌘R or Product → Run
   - The app will launch and scan your config files

### Installation

1. Build for release:
```bash
xcodebuild -project "Dot Sync.xcodeproj" \
  -scheme "Dot Sync" \
  -configuration Release \
  -archivePath "build/DotSync.xcarchive" \
  archive
```

2. Export app:
```bash
xcodebuild -exportArchive \
  -archivePath "build/DotSync.xcarchive" \
  -exportPath "build/export" \
  -exportOptionsPlist ExportOptions.plist
```

3. Copy to Applications:
```bash
cp -R "build/export/Dot Sync.app" /Applications/
```

---

## Usage

### First Launch Setup

1. Launch Dot Sync
2. App automatically scans your home directory
3. Review discovered config files (left sidebar shows categories)
4. Click "Cloud Setup" to configure your storage provider

### Configuring Cloud Storage

#### AWS S3
1. Select "AWS S3" as provider
2. Enter:
   - Bucket name
   - Region (e.g., us-east-1)
   - Access Key ID
   - Secret Access Key
3. Credentials stored securely in macOS Keychain

#### Azure Blob Storage
1. Select "Azure Blob"
2. Enter:
   - Storage account name
   - Container name
   - Tenant ID, Client ID, Client Secret

#### Google Cloud Storage
1. Select "Google Cloud Storage"
2. Enter:
   - Bucket name
   - Project ID
   - Service account key (JSON)

#### iCloud Drive
1. Select "iCloud Drive"
2. Choose folder location
3. No credentials needed (uses system authentication)

### Syncing Files

1. **Select files** to sync (checkboxes)
2. Click **"Scan"** to compare local vs remote
3. Review sync status indicators:
   - 🟢 Synced - Files match
   - 🔵 Local Newer - Your copy is newer
   - 🟠 Remote Newer - Cloud copy is newer
   - 🔴 Conflict - Both changed, need resolution
   - 🟣 Not on Remote - New file to upload
4. Click **"Sync Selected"** to execute

### Resolving Conflicts

When files conflict (both local and remote changed):

1. Conflict dialog appears automatically
2. View side-by-side diff
3. Choose resolution:
   - **Keep Local** - Upload your version
   - **Use Remote** - Download cloud version
   - **Merge Manually** - Handle outside Dot Sync
   - **Skip** - Decide later

---

## Architecture

### Project Structure

```
Dot Sync/
├── Models/
│   ├── ConfigFile.swift          # Config file data model
│   ├── CloudProvider.swift       # Cloud provider config
│   └── SyncOperation.swift       # Sync operation tracking
├── Services/
│   ├── FileDiscoveryService.swift    # Scans for config files
│   ├── SecurityScanner.swift         # Detects credentials
│   ├── CloudStorageProtocol.swift    # Cloud storage interface
│   ├── S3Provider.swift              # AWS S3 implementation
│   └── SyncEngine.swift              # Sync logic and operations
├── Views/
│   └── ContentView.swift         # Main UI
└── DotSyncApp.swift              # App entry point
```

### Key Components

**FileDiscoveryService:**
- Scans home directory for dotfiles
- Categorizes by application type
- Calculates checksums for change detection
- Determines sync priority

**SecurityScanner:**
- Scans files for credentials before sync
- Pattern matching for API keys, tokens, passwords
- Excludes SSH keys and sensitive files
- Sanitizes configs (removes auth sections)

**CloudStorageProtocol:**
- Abstract interface for cloud providers
- Upload, download, list, delete operations
- Implementations: S3, Azure, GCP, iCloud

**SyncEngine:**
- Compares local vs remote versions
- Detects conflicts
- Executes sync operations
- Manages sync state

---

## Configuration Files Supported

### Automatically Detected

**Shell Configs (Critical):**
- `.zshrc` - Zsh configuration
- `.bashrc` - Bash configuration
- `.bash_profile` - Bash profile
- `.profile` - Universal shell profile
- `.p10k.zsh` - Powerlevel10k theme

**Terminal Profiles (High Priority):**
- `~/Library/Preferences/com.apple.Terminal.plist` - Terminal.app profiles, colors, fonts
- `~/Library/Preferences/com.googlecode.iterm2.plist` - iTerm2 profiles (if installed)

**Version Control (Critical):**
- `.gitconfig` - Git global settings

**Editors (High):**
- `.vimrc` - Vim configuration
- `.vim/` - Vim plugins and settings
- `.config/Code/User/settings.json` - VS Code settings

**Cloud CLIs (High):**
- `.aws/config` - AWS CLI (credentials excluded)
- `.azure/config` - Azure CLI
- `.config/gcloud/` - Google Cloud SDK

**Development Tools (Medium):**
- `.docker/config.json` - Docker (auth removed)
- `.npmrc` - npm configuration
- `.config/gh/` - GitHub CLI

**Documentation (Low):**
- `.aws_cheatsheet.md` - AWS reference
- `.azure_cheatsheet.md` - Azure reference
- `.zsh_cheatsheet.md` - Shell reference

---

## Security

### Credential Protection

**Automatically Excluded:**
- SSH private keys (id_rsa, id_ed25519, etc.)
- AWS credentials file (.aws/credentials)
- Docker auth tokens
- npm tokens
- Command history files
- Any file matching credential patterns

**Pattern Detection:**
- Stripe API keys (sk_live_, sk_test_)
- AWS keys (AKIA...)
- Bearer tokens
- JWT tokens (eyJ...)
- Hardcoded passwords
- OAuth client secrets

**Sanitization:**
- Removes credential helpers from .gitconfig
- Strips auth tokens from Docker config
- Removes AWS credentials from config files

### Data Storage

- Credentials stored in macOS Keychain
- Optional encryption for cloud data
- Audit log of all operations
- Backup before overwrite

---

## Use Cases

### Scenario 1: New Machine Setup
1. Install Dot Sync on new Mac
2. Configure cloud provider (one-time)
3. Download all configs
4. Instantly configured development environment

### Scenario 2: Config Updates
1. Update .zshrc on Machine A
2. Dot Sync detects change
3. Sync to cloud
4. Machine B pulls update on next sync
5. Both machines stay in sync

### Scenario 3: Multiple Machines
1. Work Mac, Personal Mac, MacBook
2. All share same cloud storage
3. Configs stay synchronized
4. Conflicts detected and resolved

---

## Roadmap

### Version 1.0 (Current)
- [x] File discovery and categorization
- [x] Security scanning
- [x] AWS S3 support
- [x] Basic sync engine
- [x] SwiftUI interface
- [ ] Azure Blob support (in progress)
- [ ] Google Cloud Storage (in progress)
- [ ] iCloud Drive (in progress)

### Version 1.1 (Planned)
- [ ] Conflict resolution UI with diff view
- [ ] Scheduled auto-sync
- [ ] Menu bar app mode
- [ ] Sync notifications
- [ ] Advanced filtering
- [ ] Sync profiles (home, work, minimal)

### Version 2.0 (Future)
- [ ] Version history and rollback
- [ ] Multi-machine sync coordination
- [ ] Encrypted cloud storage
- [ ] Team sync (shared configs)
- [ ] Config templating
- [ ] Custom sync rules

---

## Troubleshooting

### Files Not Discovered
- Check file exists in home directory
- Verify file matches known patterns
- Run manual scan (click "Scan" button)

### Sync Failing
- Verify cloud credentials are correct
- Check network connectivity
- Ensure bucket/container exists
- Review Console.app for error logs

### Credentials Detected in Safe Files
- Review file content for passwords/keys
- Remove sensitive data
- Use environment variables instead
- Re-scan after cleaning

---

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create feature branch
3. Make changes
4. Add tests if applicable
5. Submit pull request

### Security

If you find a security vulnerability:
- Email: kochj@digitalnoise.net
- Subject: [SECURITY] Dot Sync Vulnerability
- Include detailed description and reproduction steps

---

## License

MIT License

Copyright (c) 2025 Jordan Koch

See LICENSE file for full details.

---

## Credits

- **Author:** Jordan Koch
- **Framework:** SwiftUI, Foundation, CryptoKit
- **Platform:** macOS 13.0+
- **Language:** Swift 5.0

---

## Version History

### v1.0.0 - December 11, 2025

**Initial Release:**
- File discovery and categorization
- Security scanning for credentials
- AWS S3 cloud storage support
- Basic sync engine
- SwiftUI native interface
- Priority-based file ranking
- Conflict detection
- Comprehensive documentation

---

**Repository:** https://github.com/kochj23/DotSync
**Status:** Active Development
**Last Updated:** December 11, 2025
