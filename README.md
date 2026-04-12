# Dot Sync

![Build](https://github.com/kochj23/DotSync/actions/workflows/build.yml/badge.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2013.0%2B-lightgrey)
![Swift](https://img.shields.io/badge/swift-5.0-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

**Smart dotfile synchronization across machines using cloud storage, with real-time file watching, credential scanning, and three-way merge.**

![Dot Sync](Screenshots/main-window.png)

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Cloud Provider Setup](#cloud-provider-setup)
- [Sync Profiles and Machine Roles](#sync-profiles-and-machine-roles)
- [Security](#security)
- [Widget Extension](#widget-extension)
- [Nova API Integration](#nova-api-integration)
- [Troubleshooting](#troubleshooting)
- [Version History](#version-history)
- [License](#license)

---

## Overview

Dot Sync is a native macOS application that synchronizes developer configuration files (dotfiles) across multiple machines through cloud storage backends. Unlike iCloud, which handles Documents and Desktop, Dot Sync targets the configuration files iCloud ignores: shell profiles, git settings, editor configs, cloud CLI configurations, and development tool preferences.

The app discovers config files automatically, scans them for credentials before upload, supports bidirectional sync with conflict resolution, and monitors files in real time for changes using DispatchSource-based file watching.

**Who this is for:**

- Developers keeping shell configs, editor settings, and tool configs in sync
- DevOps engineers synchronizing cloud CLI configurations across workstations
- System administrators maintaining consistent environments across multiple Macs
- Anyone who has spent hours rebuilding their environment on a new machine

---

## Architecture

```
+------------------------------------------------------------------+
|                        Dot Sync Application                      |
+------------------------------------------------------------------+
|                                                                  |
|  +------------------+   +------------------+   +---------------+ |
|  |   SwiftUI Views  |   |   View Models    |   |  Menu Bar     | |
|  |                  |   |                  |   |  Extra        | |
|  | ContentView      |   | DotSyncViewModel |   | MenuBarView   | |
|  | FileBrowserView  |   | CloudViewModel   |   | StatusBarView | |
|  | ConflictView     |   +--------+---------+   +-------+-------+ |
|  | PreferencesView  |            |                      |        |
|  | DiffView         |            v                      |        |
|  | VisualMergeEditor|   +--------+---------+            |        |
|  | AskAIView        |   |   Sync Engine    +<-----------+        |
|  +------------------+   |                  |                     |
|                         | - Compare local  |                     |
|                         |   vs remote      |                     |
|                         | - Detect         |                     |
|                         |   conflicts      |                     |
|                         | - Execute sync   |                     |
|                         | - Dry-run mode   |                     |
|                         +----+-------+-----+                     |
|                              |       |                           |
|               +--------------+       +---------------+           |
|               v                                      v           |
|  +------------+----------+            +--------------+--------+  |
|  | File Discovery        |            | Cloud Storage         |  |
|  | Service                |            | Protocol              |  |
|  |                       |            |                       |  |
|  | - Pattern scan ~/     |            | upload()              |  |
|  | - Categorize files    |            | download()            |  |
|  | - Checksum calc       |            | listFiles()           |  |
|  | - Priority ranking    |            | delete()              |  |
|  | - Exclude unsafe      |            | getMetadata()         |  |
|  +-----------+-----------+            | testConnection()      |  |
|              |                        +---+---+---+---+---+---+  |
|              v                            |   |   |   |   |      |
|  +-----------+-----------+                |   |   |   |   |      |
|  | Security Scanner      |                v   v   v   v   v      |
|  |                       |     +----------+--+--+--+--+--+----+  |
|  | - Regex credential    |     | S3  Azure GCP iCloud NAS     |  |
|  |   detection           |     | OneDrive  Google Drive       |  |
|  | - API key patterns    |     | S3-Compatible               |  |
|  | - Sanitize configs    |     +------------------------------+  |
|  | - Exclude SSH keys    |                                       |
|  +-----------+-----------+     +------------------------------+  |
|              |                 | File Watcher (DispatchSource) |  |
|              v                 |                              |  |
|  +-----------+-----------+     | - Per-file fd monitoring     |  |
|  | Sync Hooks            |     | - 5s debounce timer          |  |
|  |                       |     | - Auto-sync on change        |  |
|  | Pre-sync: validate    |     | - Proper fd cleanup          |  |
|  | Post-sync: reload     |     +------------------------------+  |
|  | Env var injection     |                                       |
|  | (no shell interp)    |     +------------------------------+  |
|  +-----------------------+     | Three-Way Merge              |  |
|                                |                              |  |
|  +-----------------------+     | - Ancestor/local/remote diff |  |
|  | AI Services           |     | - Auto-merge safe changes    |  |
|  |                       |     | - Conflict markers           |  |
|  | ConfigAssistant       |     +------------------------------+  |
|  | ConfigInsights        |                                       |
|  | MergeAssistant        |     +------------------------------+  |
|  | SecurityAnalyzer      |     | Widget Extension (WidgetKit) |  |
|  +-----------------------+     |                              |  |
|                                | - Small/Medium/Large sizes   |  |
|  +-----------------------+     | - Shared via App Groups      |  |
|  | Nova API Server       |     | - Timeline-based refresh     |  |
|  | (port 37446)          |     +------------------------------+  |
|  | Loopback only         |                                       |
|  +-----------------------+                                       |
|                                                                  |
+------------------------------------------------------------------+
                                  |
                                  v
                    +-------------+-------------+
                    |   macOS Keychain           |
                    |   (all credentials)        |
                    +---------------------------+
```

### Project Structure

```
DotSync/
|-- Dot Sync/
|   |-- DotSyncApp.swift              App entry point, WindowGroup, MenuBarExtra
|   |-- NovaAPIServer.swift           Local HTTP API (port 37446, loopback)
|   |-- ModernDesign.swift            Design system and theme constants
|   |-- Info.plist                    Bundle metadata (v1.2.0)
|   |-- Models/
|   |   |-- ConfigFile.swift          File model, categories, priorities, sync state
|   |   |-- CloudProvider.swift       Provider types, config, credentials
|   |   |-- SyncOperation.swift       Sync operation tracking
|   |   |-- SyncProfile.swift         Sync profiles (Full, Minimal, Work, Home)
|   |   |-- SyncProgress.swift        Progress tracking for UI
|   |   |-- SyncHooks.swift           Pre/post sync hooks with env var injection
|   |   |-- MachineInfo.swift         Machine identity, roles (Master/Client)
|   |   +-- DownloadFailure.swift     Failure tracking model
|   |-- Services/
|   |   |-- SyncEngine.swift          Core sync logic, conflict detection, state
|   |   |-- FileDiscoveryService.swift  Pattern-based config file scanner
|   |   |-- FileWatcher.swift         DispatchSource real-time monitoring
|   |   |-- SecurityScanner.swift     Credential detection and sanitization
|   |   |-- CloudStorageProtocol.swift  Abstract provider interface
|   |   |-- S3Provider.swift          AWS S3 implementation
|   |   |-- AzureBlobProvider.swift   Azure Blob Storage
|   |   |-- GCPProvider.swift         Google Cloud Storage
|   |   |-- iCloudProvider.swift      iCloud Drive (FileManager-based)
|   |   |-- NASProvider.swift         NAS via SMB/NFS
|   |   |-- OneDriveProvider.swift    Microsoft OneDrive
|   |   |-- GoogleDriveProvider.swift Google Drive
|   |   |-- AWSHelper.swift           AWS authentication utilities
|   |   |-- ThreeWayMerge.swift       Line-by-line three-way merge
|   |   |-- NotificationService.swift macOS notification delivery
|   |   +-- AI/
|   |       |-- AIConfigAssistant.swift    AI-powered config help
|   |       |-- AIConfigInsights.swift     Configuration analysis
|   |       |-- AIMergeAssistant.swift     AI-assisted merge resolution
|   |       +-- AISecurityAnalyzer.swift   AI security scanning
|   +-- Views/
|       |-- ContentView.swift         Main window layout
|       |-- AskAIView.swift           AI assistant interface
|       |-- AIFeaturesDashboard.swift  AI features overview
|       |-- ConflictResolutionView.swift  Conflict dialog
|       |-- DiffView.swift            Side-by-side diff display
|       |-- VisualMergeEditor.swift   Interactive merge editor
|       |-- PreferencesView.swift     Settings panel
|       |-- MenuBarView.swift         Menu bar dropdown
|       |-- StatusBarView.swift       Bottom status bar
|       |-- SyncProgressView.swift    Sync progress indicators
|       |-- FailureSummaryView.swift  Error report display
|       +-- ToastNotificationView.swift  Toast-style alerts
|-- Dot Sync Widget/
|   |-- DotSyncWidget.swift           WidgetKit extension (S/M/L)
|   +-- Info.plist
|-- Shared/
|   |-- SharedDataManager.swift       App Groups data bridge
|   +-- WidgetData.swift              Widget data models
|-- Dot Sync.xcodeproj/
|-- .github/
|   |-- workflows/build.yml           CI build verification
|   |-- ISSUE_TEMPLATE/
|   |-- PULL_REQUEST_TEMPLATE.md
|   +-- dependabot.yml
|-- LICENSE                           MIT License
|-- SECURITY.md                       Security policy
+-- CLOUD_SETUP_GUIDE.md             Detailed provider setup
```

---

## Features

### Config File Discovery

Dot Sync scans the home directory for known configuration file patterns and organizes them by category:

| Category      | Files                                                        | Priority |
|---------------|--------------------------------------------------------------|----------|
| Shell         | .zshrc, .bashrc, .bash_profile, .profile, .p10k.zsh, .fzf.* | Critical |
| Git           | .gitconfig, .gitignore_global                                | Critical |
| Editor        | .vimrc, .vim/, VS Code settings, Neovim config               | High     |
| Cloud         | .aws/config, .azure/config, .config/gcloud/                  | High     |
| Terminal      | Terminal.app plist, iTerm2 plist                              | High     |
| Docker        | .docker/config.json (auth stripped), .dockerignore            | Medium   |
| Language      | .npmrc, .gemrc, .pypirc, .cargo/config                       | Medium   |
| Claude        | .claude/CLAUDE.md, .claude/settings.json                     | Medium   |
| Documentation | Cheatsheets (.aws_cheatsheet.md, etc.)                       | Low      |

### Cloud Storage Providers

Eight storage backends, all conforming to the `CloudStorageProtocol` interface:

| Provider         | Authentication               | Notes                          |
|------------------|------------------------------|--------------------------------|
| AWS S3           | Access Key + Secret Key      | Full S3 API                    |
| Azure Blob       | Tenant + Client ID + Secret  | Azure Storage REST API         |
| Google Cloud     | Project ID + Service Account | GCS JSON API                   |
| iCloud Drive     | System authentication        | No credentials needed          |
| NAS (SMB/NFS)    | Username + Password + Path   | Local network storage          |
| OneDrive         | Client ID + Secret + Token   | Microsoft Graph API            |
| Google Drive     | Client ID + Secret + Token   | Google Drive API               |
| S3-Compatible    | Access Key + Secret Key      | MinIO, Wasabi, Backblaze, etc. |

All credentials are stored in the macOS Keychain. Never in UserDefaults, plists, or files.

### Real-Time File Watching

The `FileWatcher` service uses `DispatchSource.makeFileSystemObjectSource` to monitor individual files via file descriptors. This replaced an earlier FSEvents implementation that caused crashes.

How it works:

1. Each watched file gets an `O_EVTONLY` file descriptor
2. A `DispatchSourceFileSystemObject` monitors `.write` and `.attrib` events
3. Changes trigger a 5-second debounce timer to batch rapid edits
4. After debounce, the file is auto-synced (if enabled) or a notification is shown
5. Cancel handlers close file descriptors on cleanup

### Three-Way Merge

When both local and remote copies have changed, Dot Sync performs a line-by-line three-way merge using the last-known common ancestor. Changes that do not overlap are merged automatically. True conflicts produce standard conflict markers (`<<<<<<< LOCAL` / `=======` / `>>>>>>> REMOTE`) for manual resolution.

### Sync Hooks

Pre-sync and post-sync shell hooks run before and after file synchronization. File metadata (name, path, category) is passed via environment variables (`$SYNC_FILENAME`, `$SYNC_FILEPATH`, `$SYNC_CATEGORY`) rather than string interpolation, preventing command injection through crafted filenames.

Default hooks:
- **Pre-sync:** `zsh -n ~/.zshrc` (syntax validation before upload)
- **Post-sync:** `git config --list > /dev/null` (verify git config after download)

### Sync Profiles

Four built-in profiles control which file categories get synced:

| Profile  | Categories Included                          |
|----------|----------------------------------------------|
| Full     | All detected config files                    |
| Minimal  | Shell + Git only                             |
| Work     | Shell, Git, Cloud, Claude, Docker            |
| Home     | Shell, Git, Editor, Claude                   |

Custom profiles can be created with arbitrary category and file selections.

### Machine Roles

Each machine is assigned a role that controls sync direction:

- **Master** -- Can upload and download. The authoritative source of config files.
- **Client** -- Download only. Receives configs from the master but does not push changes.

Machines are identified by their hardware UUID (via `IOPlatformExpertDevice`), providing stable identity across reboots.

### AI-Assisted Features

Four AI service modules provide intelligent assistance:

- **AIConfigAssistant** -- Answers questions about config file syntax and options
- **AIConfigInsights** -- Analyzes configurations for optimization opportunities
- **AIMergeAssistant** -- Helps resolve complex merge conflicts
- **AISecurityAnalyzer** -- Scans configs for security issues beyond regex patterns

### Menu Bar Integration

Dot Sync lives in the macOS menu bar with a status icon that reflects current state:

- Checkmark (green) -- All files synced
- Arrows (yellow) -- Files need sync
- Warning triangle (red) -- Conflicts detected
- Rotating arrows (blue) -- Sync in progress
- Cloud (gray) -- Not yet synced

---

## Installation

**Dot Sync is distributed as a DMG installer. It is not available on the Mac App Store.**

### Option 1: DMG Installer (Recommended)

1. Download the latest DMG from [Releases](https://github.com/kochj23/DotSync/releases)
2. Open the DMG and drag `Dot Sync.app` to the Applications folder
3. Launch from Applications or Spotlight

### Option 2: Build from Source

```bash
# Clone the repository
git clone https://github.com/kochj23/DotSync.git
cd DotSync

# Open in Xcode
open "Dot Sync.xcodeproj"

# Build and run (Cmd+R) or build for release:
xcodebuild -project "Dot Sync.xcodeproj" \
  -scheme "Dot Sync" \
  -configuration Release \
  -archivePath "build/DotSync.xcarchive" \
  archive
```

### Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0+ (building from source only)
- A cloud storage account (AWS, Azure, GCP, iCloud, NAS, OneDrive, or Google Drive)

### Dependencies

None. Dot Sync uses only built-in macOS frameworks:

- **SwiftUI** -- User interface
- **Foundation** -- Core functionality
- **CryptoKit** -- Checksums and encryption
- **Combine** -- Reactive data flow
- **Network** -- Nova API server (NWListener)
- **WidgetKit** -- macOS widget extension
- **SystemConfiguration** -- Machine identification

---

## Configuration

### First Launch

1. Launch Dot Sync
2. The app automatically scans your home directory for config files
3. Review discovered files in the sidebar (organized by category and priority)
4. Click "Cloud Setup" to configure your storage provider

### Sync Workflow

**Manual sync:**
1. Select files to sync (checkboxes in the file list)
2. Click "Scan" to compare local vs remote timestamps and checksums
3. Review sync status for each file:
   - Green (Synced) -- Files match
   - Blue (Local Newer) -- Your copy is newer, will upload
   - Orange (Remote Newer) -- Cloud copy is newer, will download
   - Red (Conflict) -- Both changed, needs resolution
   - Purple (Not on Remote) -- New file, will upload
4. Click "Sync Selected" to execute
5. Use Cmd+Shift+S for quick sync of all safe files

**Auto-sync:**
1. Enable Auto-Sync in Preferences
2. Dot Sync monitors selected files via DispatchSource
3. Changes trigger automatic upload after a 5-second debounce
4. Disable auto-sync at any time to return to manual control

---

## Cloud Provider Setup

### AWS S3

```bash
# Create an S3 bucket
aws s3 mb s3://my-dotfiles --region us-east-1

# Enable versioning (recommended)
aws s3api put-bucket-versioning \
  --bucket my-dotfiles \
  --versioning-configuration Status=Enabled

# Enable server-side encryption
aws s3api put-bucket-encryption \
  --bucket my-dotfiles \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

In Dot Sync: select "AWS S3", enter the bucket name, region, access key ID, and secret access key. Credentials are stored in the macOS Keychain.

### Azure Blob Storage

```bash
# Create storage account
az storage account create \
  --name mydotfiles \
  --resource-group my-rg \
  --location eastus \
  --sku Standard_LRS

# Create container
az storage container create \
  --name dotfiles \
  --account-name mydotfiles
```

In Dot Sync: select "Azure Blob", enter the storage account name, container name, tenant ID, client ID, and client secret.

### Google Cloud Storage

```bash
# Create bucket
gsutil mb -p my-project gs://my-dotfiles

# Enable versioning
gsutil versioning set on gs://my-dotfiles
```

In Dot Sync: select "Google Cloud Storage", enter the bucket name, project ID, and upload your service account key JSON.

### iCloud Drive

Select "iCloud Drive" and choose a folder location. No credentials are needed -- the app uses macOS system authentication.

### NAS (SMB/NFS)

Select "NAS (SMB/NFS)" and enter the server address, share path, username, and password. The NAS must be reachable on the local network.

### OneDrive / Google Drive

Select the provider and enter the OAuth client ID, client secret, and refresh token. Token refresh is handled automatically.

---

## Sync Profiles and Machine Roles

### Profiles

Switch between profiles in the sidebar or Preferences to control which categories of files participate in sync operations. Create custom profiles by selecting specific categories and individual files.

### Master / Client Topology

On your primary machine, set the role to **Master**. All other machines should be **Client**. This prevents accidental overwrites -- clients pull configs from the master but never push changes back.

The role is stored locally per machine and can be changed at any time in Preferences.

---

## Security

### What Never Gets Synced

These files and patterns are excluded automatically:

- SSH private keys (id_rsa, id_dsa, id_ecdsa, id_ed25519)
- Credential files (.aws/credentials, .npmrc with auth tokens)
- Command history (.bash_history, .zsh_history, .lesshst, .viminfo)
- Cache directories
- Binary files
- Swap and temp files (.swp, .tmp, .temp)
- Any file matching credential regex patterns

### Credential Detection

The `SecurityScanner` checks every file against regex patterns before allowing sync:

- Stripe API keys (sk_live_, sk_test_, pk_live_)
- AWS access keys (AKIA...)
- Bearer tokens
- JWT tokens (eyJ...)
- Hardcoded passwords
- SSH private key headers
- OAuth client secrets
- GCP service account JSON markers

Files flagged by the scanner are marked `isSafeToSync = false` and will not upload.

### Sanitization

When safe files contain isolated credential fragments (like a git credential helper line), the scanner can sanitize the content before upload:

- Removes credential helper sections from .gitconfig
- Strips auth tokens from Docker config
- Removes AWS access key lines from config files

### Data Storage

- **Credentials:** macOS Keychain (via Security framework). Never UserDefaults.
- **Cloud data:** Optional AES-256 encryption at rest
- **Backups:** .backup file created before any overwrite
- **Audit log:** All operations logged with timestamps
- **No telemetry:** Zero data sent to external services

### Command Injection Prevention

Sync hooks pass file metadata via environment variables instead of interpolating filenames into shell commands. A file named `; rm -rf /` will not execute -- it appears only as the value of `$SYNC_FILENAME`.

---

## Widget Extension

Dot Sync includes a macOS WidgetKit extension with three sizes:

| Size   | Content                                                          |
|--------|------------------------------------------------------------------|
| Small  | Sync status ring, machine count, last sync time                  |
| Medium | Status + recent files synced + conflict count + cloud provider   |
| Large  | Per-machine sync status, recent sync history, conflict details   |

Widget data is shared from the main app via App Groups (`group.com.jkoch.dotsync`) using a `SharedDataManager` that writes `WidgetSyncData` to shared UserDefaults.

---

## Nova API Integration

Dot Sync exposes a local HTTP API on port **37446** for integration with Nova (OpenClaw AI) and Claude Code.

The server binds to `127.0.0.1` only -- no external network exposure. No authentication is required (loopback only).

### Endpoints

```
GET /api/status   -- App status, version, uptime
GET /api/ping     -- Health check (returns pong)
```

### Example

```bash
curl -s http://127.0.0.1:37446/api/status | python3 -m json.tool
```

The API server starts automatically when the app launches.

---

## Troubleshooting

**Files not discovered:**
Check that the file exists in the home directory and matches a known pattern. Run File > Rescan manually. Check Console.app for scanning errors.

**Sync failing:**
Verify cloud credentials (Settings > Cloud). Test network connectivity. Ensure the bucket or container exists. Check Console.app for API errors.

**Auto-sync not working:**
Verify Auto-Sync is enabled in Preferences. Check file descriptor limits (`ulimit -n`). Review Console.app for DispatchSource errors. Restart the app if file watching has stopped.

**Credentials detected in safe files:**
Review the file for passwords or keys. Remove sensitive data or switch to environment variables. Add the file to the exclusion list if the detection is a false positive.

**High CPU usage:**
Disable auto-sync temporarily. Reduce the number of monitored files. Increase the debounce interval in Settings.

**Conflict resolution loop:**
Choose "Keep Local" or "Use Remote" definitively. Avoid repeatedly skipping conflicts. For complex configs, export both versions and merge manually.

---

## Version History

### v1.2.0 (March 2026) -- Current

- Widget Extension target connected and building
- FileWatcher rewritten with DispatchSource (replaced FSEvents)
- All file watching crashes eliminated
- Memory-safe file descriptor cleanup
- 5-second debounce on change events
- Lower CPU usage with event-driven monitoring

### v1.1.0 (December 2025)

- Terminal.app and iTerm2 profile sync
- Azure Blob Storage support
- Google Cloud Storage support
- iCloud Drive integration
- Improved file browser with icons and categories

### v1.0.0 (December 2025) -- Initial Release

- Config file discovery and categorization
- Security scanning for credentials
- AWS S3 cloud storage support
- Core sync engine with conflict detection
- SwiftUI native interface
- Priority-based file ranking

---

## License

MIT License

Copyright (c) 2025-2026 Jordan Koch

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, subject to the conditions in the [LICENSE](LICENSE) file.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED. See LICENSE for full terms.

---

## More Apps by Jordan Koch

| App | Description |
|-----|-------------|
| [RsyncGUI](https://github.com/kochj23/RsyncGUI) | Native macOS GUI for rsync file synchronization |
| [TopGUI](https://github.com/kochj23/TopGUI) | macOS system monitor with real-time metrics |
| [ExcelExplorer](https://github.com/kochj23/ExcelExplorer) | Native macOS Excel/CSV file viewer |
| [icon-creator](https://github.com/kochj23/icon-creator) | App icon set generator for all Apple platforms |
| [MBox-Explorer](https://github.com/kochj23/MBox-Explorer) | macOS mbox email archive viewer |

[View all projects](https://github.com/kochj23?tab=repositories)

---

Written by Jordan Koch ([@kochj23](https://github.com/kochj23)).

> Disclaimer: This is a personal project created on my own time. It is not affiliated with, endorsed by, or representative of my employer.
