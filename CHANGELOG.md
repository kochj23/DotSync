# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Performance improvements
- Additional features based on community feedback

## [1.3.0] - 2026-11-11

### Changed
- AI: migrated to NovaAIKit 1.0.0 (AI on/off, Auto failover across Ollama, MLX, TinyChat, TinyLLM, OpenWebUI,
  Nova Gateway, OpenRouter and OpenAI; model picker; editable URLs; status indicator; timeouts and retries).
- Every AI feature validates the reply (format check, clamped values, one retry) and falls back to built-in rules
  when AI is off, unreachable or rejected. Results are labeled "AI · <backend>" or "Built-in".
- New Settings > AI tab (NovaAISettingsView).

### Security
- AI keys live only in the Keychain (`com.jkoch.dotsync.<backend>`) and are only sent over https. A legacy OpenAI key
  in the old `com.jordankoch.DotSync` service or in UserDefaults is moved once; Google/Azure/AWS/IBM AI secrets are
  deleted.

### Removed
- The app's own AI client (`AIBackendManager` and its dead copies, `AIBackendStatusMenu`) and the Google Cloud,
  Azure, AWS and IBM Watson AI backends.

### Fixed
- All build warnings (Swift 6 concurrency warnings in file discovery / iCloud / NAS enumeration, unused values,
  missing AccentColor, widget build-number mismatch).

## [1.2.0] - 2026-03-01

### Added
- Widget extension; DispatchSource FileWatcher.

## [1.0.0] - 2025-01-01

### Added
- Initial release
- Core functionality
- macOS native interface
- MIT License

---

*For detailed release notes, see [GitHub Releases](https://github.com/kochj23/DotSync/releases).*
