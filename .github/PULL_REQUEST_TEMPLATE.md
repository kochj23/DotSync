# Pull Request

## 📝 Description

<!-- Provide a detailed description of your changes -->

### Summary
<!-- Brief one-line summary -->

### Changes Made
-
-
-

---

## 🎯 Type of Change

**Select all that apply:**

- [ ] 🐛 Bug fix (non-breaking change that fixes an issue)
- [ ] ✨ New feature (non-breaking change that adds functionality)
- [ ] 💥 Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] 🔒 Security fix (addresses a security vulnerability)
- [ ] ⚡ Performance improvement
- [ ] ♻️ Refactoring (code change that neither fixes a bug nor adds a feature)
- [ ] 📝 Documentation update
- [ ] 🧪 Test coverage improvement
- [ ] 🎨 UI/UX improvement

---

## 🔒 Security Review Checklist

**IMPORTANT:** All PRs must pass security review

- [ ] **No hardcoded secrets** - API keys, passwords, tokens stored in Keychain
- [ ] **Input validation** - All user input properly validated and sanitized
- [ ] **XSS prevention** - JavaScript injection properly escaped (use JSON encoding)
- [ ] **Certificate pinning** - Not disabled or weakened
- [ ] **Logging security** - No sensitive data logged (tokens, passwords, PII)
- [ ] **URL navigation** - Respects domain allowlist, no unauthorized domains added
- [ ] **Encryption** - AES-256-GCM used for sensitive data
- [ ] **Memory management** - Used `[weak self]` in closures, no retain cycles
- [ ] **Memory leak check** - Ran `/memory-check` on modified files
- [ ] **Biometric auth** - Not bypassed or weakened

**Security Impact Assessment:**
- [ ] This PR has NO security implications
- [ ] This PR has security implications (describe below)

<!-- If security implications exist, describe them: -->

---

## 🧪 Testing Checklist

- [ ] **Unit tests** - Added/updated for new functionality
- [ ] **Integration tests** - Pass for affected flows
- [ ] **Manual testing** - Tested on iPhone
- [ ] **Manual testing** - Tested on iPad
- [ ] **Build verification** - Debug and Release builds succeed
- [ ] **No warnings** - Build completes without compiler warnings
- [ ] **Code coverage** - Maintains or improves coverage (≥80%)

**Test Results:**
<!-- Paste relevant test output or screenshots -->

---

## 📱 Platforms Tested

**iPhone:**
- [ ] iPhone 15 Pro (or specify model)
- [ ] iOS 18.0 (or specify version)

**iPad:**
- [ ] iPad Pro (or specify model)
- [ ] iPadOS 18.0 (or specify version)

**Simulator:**
- [ ] iPhone Simulator
- [ ] iPad Simulator

---

## 📸 Screenshots

<!-- If UI changes, add before/after screenshots -->

**Before:**
<!-- Drag and drop screenshot -->

**After:**
<!-- Drag and drop screenshot -->

---

## 🔗 Related Issues

Closes #<!-- issue number -->
Fixes #<!-- issue number -->
Related to #<!-- issue number -->

---

## 📚 Documentation

- [ ] **Code comments** - Added for complex logic
- [ ] **README updated** - If user-facing changes
- [ ] **CHANGELOG updated** - If significant change
- [ ] **API documentation** - If public APIs changed

---

## ⚡ Performance Impact

**Does this PR affect performance?**
- [ ] No performance impact
- [ ] Improves performance
- [ ] May impact performance (profiling needed)

**If performance impact, provide details:**
<!-- Memory usage, CPU usage, battery impact, launch time, etc. -->

---

## 🎨 Code Quality

- [ ] **SwiftLint** - Passes without new warnings
- [ ] **Xcode Analyzer** - No new static analysis warnings
- [ ] **Code style** - Follows project conventions
- [ ] **DRY principle** - No unnecessary code duplication
- [ ] **Single Responsibility** - Functions do one thing well
- [ ] **Error handling** - Comprehensive try/catch where needed

---

## 🔄 Migration Required

**Does this PR require data migration?**
- [ ] No migration needed
- [ ] Migration needed (describe below)

<!-- If migration needed, describe the migration strategy: -->

---

## 📋 Reviewer Notes

**Areas requiring extra attention:**
<!-- Point reviewers to specific areas that need careful review -->

**Questions for reviewers:**
<!-- Any specific questions or concerns? -->

---

## ✔️ Pre-Submission Checklist

- [ ] I have performed a self-review of my code
- [ ] I have commented my code where necessary
- [ ] I have updated relevant documentation
- [ ] I have added tests that prove my fix is effective or feature works
- [ ] All new and existing tests pass locally
- [ ] I have checked for memory leaks with `/memory-check`
- [ ] I have verified no hardcoded secrets are included
- [ ] My changes generate no new compiler warnings
- [ ] I have reviewed the security checklist above
- [ ] I have tested on both iPhone and iPad (if UI changes)

---

## 🚀 Deployment Notes

**Special deployment considerations:**
<!-- Anything special needed when deploying this change? -->

**Rollback plan:**
<!-- How to rollback if issues are found? -->

---

**PR Author:** @<!-- your GitHub username -->
**Created:** <!-- date -->
