# Keychain Storage

This document explains how ActivityBar stores and manages OAuth tokens and credentials using macOS Keychain.

## Table of Contents

- [Overview](#overview)
- [Storage Architecture](#storage-architecture)
- [Token Management](#token-management)
- [Security Model](#security-model)
- [Password Prompts](#password-prompts)
- [Token Lifecycle](#token-lifecycle)
- [Error Handling](#error-handling)

## Overview

ActivityBar uses macOS Keychain Services to securely store OAuth tokens for authenticated provider accounts. The implementation prioritizes:

- **Minimal password prompts**: Users see at most 1-2 password prompts per session
- **Secure storage**: All tokens encrypted by macOS Keychain
- **Session caching**: Tokens loaded once and cached in memory
- **Atomic operations**: All tokens saved/loaded together

## Storage Architecture

### Single Keychain Item Design

All tokens for all accounts are stored in a **single keychain item** with JSON blob format:

```
Keychain Item Details:
┌──────────────────────────────────────────────────┐
│ Service:  com.activitybar.tokens                 │
│ Account:  all-tokens                             │
│ Kind:     Generic Password                       │
│ Access:   After First Unlock                     │
├──────────────────────────────────────────────────┤
│ Value (JSON):                                    │
│ {                                                │
│   "gitlab:username": {                           │
│     "access": "glpat-xxx...",                    │
│     "refresh": "refresh_xxx..."                  │
│   },                                             │
│   "google-calendar:user@example.com": {          │
│     "access": "ya29.xxx...",                     │
│     "refresh": "1//xxx..."                       │
│   },                                             │
│   "azure:userid": {                              │
│     "access": "eyJ0xxx...",                      │
│     "refresh": null                              │
│   }                                              │
│ }                                                │
└──────────────────────────────────────────────────┘
```

### Account Key Format

Tokens are keyed by account identifier:

| Provider Type | Key Format | Example |
|--------------|------------|---------|
| Cloud (GitLab, Google) | `provider:accountId` | `gitlab:johndoe` |
| Self-hosted GitLab | `provider:host:accountId` | `gitlab:git.company.com:johndoe` |
| Azure DevOps | `azure:userId` | `azure:abc123-def456` |

### Token Pair Structure

Each account stores two tokens:

```json
{
  "access": "string",   // Access token for API calls
  "refresh": "string"   // Refresh token to obtain new access tokens (optional)
}
```

**Note:** Azure DevOps uses Personal Access Tokens (PATs) which don't have refresh tokens, so `refresh` will be `null`.

## Token Management

### Load-Once Pattern

Tokens are loaded from keychain **once per app session**:

```
App Launch
    ↓
First Token Access (getToken/setToken)
    ↓
loadCacheIfNeeded()
    ├─→ SecItemCopyMatching (keychain read)  ← PASSWORD PROMPT (if locked)
    ├─→ Deserialize JSON blob
    ├─→ Store in memory cache
    └─→ Set cacheLoaded = true
    ↓
All Subsequent Operations
    └─→ Read/write from memory cache (NO keychain access)
```

### Token Operations

#### Retrieving Tokens

```swift
// Access token
let accessToken = try await tokenStore.getToken(for: "gitlab:username")

// Refresh token
let refreshToken = try await tokenStore.getToken(for: "gitlab:username:refresh")
```

**Flow:**
1. Check if cache loaded, load if needed (first call only)
2. Parse account key to extract base ID and token type
3. Return from in-memory cache

**Keychain Access:** Once (first call), then cached

#### Storing Tokens

```swift
// Store access token
try await tokenStore.setToken(accessToken, for: "gitlab:username")

// Store refresh token
try await tokenStore.setToken(refreshToken, for: "gitlab:username:refresh")
```

**Flow:**
1. Check if cache loaded, load if needed (first call only)
2. Parse account key to extract base ID and token type
3. Update token pair in memory cache
4. Serialize entire cache to JSON
5. Save to keychain with `SecItemUpdate`

**Keychain Access:** Once per `setToken()` call (write operation)

#### Deleting Tokens

```swift
// Delete specific token
try await tokenStore.deleteToken(for: "gitlab:username:refresh")

// Delete entire account (both tokens)
try await tokenStore.deleteToken(for: "gitlab:username")
```

**Flow:**
- If deleting `:refresh` suffix → Clear only refresh token, keep access token
- Otherwise → Remove entire account from cache
- Save updated cache to keychain

**Keychain Access:** Once (write operation)

## Security Model

### Keychain Access Control

Tokens are stored with `kSecAttrAccessibleAfterFirstUnlock`:

| Access Level | Meaning |
|-------------|---------|
| After First Unlock | Data accessible after user unlocks device for the first time after boot |
| Password Protection | Keychain item requires user password if keychain is locked |
| App Sandboxing | Only ActivityBar can access its keychain items |

### Code Signing Implications

The keychain uses app code signature to determine access:

| Signing Type | Behavior | Use Case |
|-------------|----------|----------|
| **Ad-hoc signing** (`codesign -s -`) | Signature changes each build → Password prompts on each run | Development |
| **Developer ID** (Apple Developer account) | Consistent signature → "Always Allow" persists between builds | Production |
| **Self-signed certificate** | Consistent signature (better than ad-hoc) | Advanced development |

**Development Note:** With ad-hoc signing, macOS sees each build as a "different app" attempting to access the keychain, triggering password prompts even if previously allowed.

### Encryption

All keychain data is encrypted by macOS using:
- User's login keychain password (master key)
- AES-128 encryption for keychain items
- Hardware-backed encryption on Apple Silicon

ActivityBar does **not** implement additional encryption—relying on macOS Keychain's security guarantees.

## Password Prompts

### When Prompts Occur

| Scenario | Keychain Access | Password Prompt |
|----------|----------------|-----------------|
| **App startup (first token access)** | 1 read (`SecItemCopyMatching`) | **Yes** (if keychain locked) |
| **Subsequent token reads** | 0 (cached in memory) | **No** |
| **Token updates (OAuth, refresh)** | 1 write per update (`SecItemUpdate`) | **No** (already unlocked from load) |
| **New account added** | 1 write (`SecItemUpdate`) | **No** (already unlocked) |
| **Account removed** | 1 write (`SecItemUpdate`) | **No** (already unlocked) |

### Minimizing Prompts

**Before refactoring (multi-item storage):**
- 1 prompt per token read (4+ tokens = 4+ prompts)
- 1 prompt per token write
- **Result:** 5-10 prompts per session

**After refactoring (single-item storage):**
- 1 prompt on first access (loads all tokens)
- 0 prompts for reads (cached)
- 0 prompts for writes (keychain already unlocked)
- **Result:** 1-2 prompts per session maximum

### User Experience

On first run or after Mac restart:

```
1. User launches ActivityBar
2. App attempts to load tokens from keychain
3. macOS prompts: "ActivityBarApp wants to access key 'all-tokens' in your keychain"
4. User clicks "Always Allow"
5. All tokens loaded into memory
6. No further prompts for entire session
```

### Avoiding Prompts in Development

**Option 1: Click "Always Allow"** (temporary—breaks on rebuild with ad-hoc signing)

**Option 2: Use a self-signed certificate:**
1. Open Keychain Access
2. Keychain Access → Certificate Assistant → Create a Certificate
3. Name: "ActivityBar Developer"
4. Type: Code Signing
5. Build and sign: `codesign -s "ActivityBar Developer" .build/release/ActivityBarApp`

**Option 3: Build once, run many times** (don't rebuild between runs)

## Token Lifecycle

### OAuth Flow (New Account)

```
User initiates OAuth flow
    ↓
Browser-based authentication
    ↓
Receive authorization code
    ↓
Exchange code for tokens
    ├─→ Access Token
    └─→ Refresh Token
    ↓
Store in TokenStore
    ├─→ setToken(access, for: "provider:account")
    └─→ setToken(refresh, for: "provider:account:refresh")
    ↓
Save to keychain (2 writes, both update same JSON blob)
```

### Token Refresh (Expired Access Token)

```
API request fails with 401 Unauthorized
    ↓
TokenRefreshService detects expired token
    ↓
Retrieve refresh token
    ├─→ getToken(for: "provider:account:refresh")
    └─→ Read from memory cache (no keychain access)
    ↓
Exchange refresh token for new access token
    ↓
Update TokenStore
    ├─→ setToken(newAccess, for: "provider:account")
    └─→ Save to keychain (1 write)
    ↓
Retry original API request with new token
```

### Account Removal

```
User removes account in Settings
    ↓
Delete tokens
    ├─→ deleteToken(for: "provider:account")
    └─→ Removes entire account from cache
    ↓
Save to keychain (1 write)
```

## Error Handling

### Keychain Errors

| Error Code | Constant | Meaning | Recovery |
|-----------|----------|---------|----------|
| `-25300` | `errSecItemNotFound` | Token not found | Treat as missing, re-authenticate |
| `-25293` | `errSecAuthFailed` | User denied access | Prompt user to allow access |
| `-34018` | (iOS-specific) | Keychain access issue | N/A on macOS |
| `0` | `errSecSuccess` | Success | Continue normally |

### Token Store Errors

```swift
public enum TokenStoreError: Error {
    case keychainError(OSStatus)     // Keychain API error
    case dataEncodingError           // Failed to encode token as UTF-8
    case dataDecodingError           // Failed to decode token from data
}
```

### Handling Missing Tokens

When `getToken()` returns `nil`:

```swift
guard let token = try await tokenStore.getToken(for: accountId) else {
    // Token not found - user needs to re-authenticate
    // Show OAuth flow or settings
    return
}
```

### Handling Corrupted Cache

If JSON deserialization fails:
1. Log error
2. Start with empty cache
3. User will need to re-authenticate all accounts

**Data loss prevention:** Manual backup of keychain recommended before major updates.

## Developer Notes

### Testing with Keychain

Tests use isolated service names to avoid conflicts:

```swift
let testStore = KeychainTokenStore(
    serviceName: "com.activitybar.tokens.test-\(UUID().uuidString)"
)
```

This ensures:
- Tests don't interfere with production tokens
- Each test run uses a fresh keychain namespace
- Cleanup happens automatically (unique service names)

### Debugging Keychain Access

Enable keychain logging:

```swift
// In KeychainTokenStore, logging already included:
print("[ActivityBar][Keychain] Loading all tokens from keychain (single item)...")
print("[ActivityBar][Keychain] Loaded \(tokenCache.count) accounts from keychain")
print("[ActivityBar][Keychain] Saving \(tokenCache.count) accounts to keychain...")
```

View keychain items manually:

```bash
# List all ActivityBar keychain items
security find-generic-password -s "com.activitybar.tokens"

# Dump keychain item (shows metadata, not password)
security find-generic-password -s "com.activitybar.tokens" -a "all-tokens"

# Delete keychain item (for testing)
security delete-generic-password -s "com.activitybar.tokens" -a "all-tokens"
```

### Migration from Old Format

If upgrading from a version that used per-token keychain items:

**No automatic migration.** Users must:
1. Remove all accounts in Settings
2. Re-authenticate each account
3. Tokens stored in new single-item format

**Manual migration script** (if needed):
```swift
// Pseudocode
let oldKeys = ["gitlab:user", "gitlab:user:refresh", "google:email", ...]
var newCache: [String: TokenPair] = [:]

for key in oldKeys {
    if let token = try? oldStore.getToken(for: key) {
        let (base, isRefresh) = parseKey(key)
        if isRefresh {
            newCache[base]?.refresh = token
        } else {
            newCache[base] = TokenPair(access: token, refresh: nil)
        }
    }
}

try newStore.saveCacheToKeychain(newCache)
```

---

**Related Documentation:**
- [Architecture](architecture.md) - Overall app architecture
- [Providers](providers.md) - OAuth and API integration
- [Development](development.md) - Development setup and workflows
