---
applyTo: "Modules/CIPPCore/Public/GraphHelper/**"
description: "Use when working with authentication, token acquisition, Graph/Exchange API helpers, or SAM/GDAP concepts. Also consult when making API calls with -scope, -tenantid, or -AsApp parameters, or when interfacing with a new Microsoft API scope. Covers the Secure Application Model, token flows, credential storage, caching, scopes, and developer rules."
---

# CIPP Authentication & Token Model

CIPP is a **multi-tenant partner management tool**. It does not use per-tenant app registrations. A single **Secure Application Model (SAM)** app in the partner's tenant accesses all customer tenants via delegated admin relationships.

## Credential storage

Credentials are loaded via `Get-CIPPAuthentication`, which reads from **Azure Key Vault** (production) or **DevSecrets table** (local development) and sets environment variables:

| Variable | Source | Purpose |
|----------|--------|---------|
| `$env:ApplicationID` | Key Vault / DevSecrets | SAM app client ID |
| `$env:ApplicationSecret` | Key Vault / DevSecrets | SAM app client secret |
| `$env:RefreshToken` | Key Vault / DevSecrets | Partner user's delegated refresh token |
| `$env:TenantID` | Key Vault / DevSecrets | Partner tenant GUID |

`Get-CIPPAuthentication` is called lazily by `Get-GraphToken` when `$env:SetFromProfile` is not set. It also re-fires when the `AppCache` config row shows a different `ApplicationId` than the current environment.

## Token acquisition flow

All token calls flow through `Get-GraphToken`:

```
New-GraphGetRequest / New-ExoRequest / New-TeamsRequest / etc.
        │ (internal call)
        ▼
    Get-GraphToken($tenantid, $scope, $AsApp)
        │
        ├─ Check process-wide .NET cache: [CIPP.CIPPTokenCache]::Lookup(key, 120)
        │    └─ Hit + not expired → return cached token
        │
        ├─ Determine grant type:
        │    ├─ $AsApp = $true  → client_credentials (app-only)
        │    └─ $AsApp = $false → refresh_token (delegated, default)
        │
        ├─ Determine refresh token:
        │    ├─ Direct tenant → lazy-load tenant-specific token from Key Vault
        │    └─ GDAP tenant  → use partner's $env:RefreshToken
        │
        └─ POST to login.microsoftonline.com/{tenantid}/oauth2/v2.0/token
             │
             └─ Cache result via [CIPP.CIPPTokenCache]::Store(key, json, expiresOn)
```

The `-tenantid` parameter **drives token acquisition**, not just filtering. It determines which customer tenant the token is issued for.

## Token modes

### Delegated (default)

App acts on behalf of the partner user's delegated permissions. Uses `refresh_token` grant.

```powershell
New-GraphGetRequest -uri '...' -tenantid $TenantFilter
```

### App-only (`-AsApp $true`)

App acts as itself with application-level permissions. Uses `client_credentials` grant.

```powershell
New-GraphGetRequest -uri '...' -tenantid $TenantFilter -AsApp $true
```

**Delegated is always the default.** Only use `-AsApp $true` when one of the following applies:

1. **No delegated path exists** — the API or endpoint only supports application permissions (e.g., certain Teams channel operations where user permissions are layered on top of roles).
2. **Crossing the customer-data barrier** — the operation must bypass user-level permission layering imposed by the service (Teams/SharePoint are the primary example).
3. **Break-glass / CA bypass** — the developer is explicitly building fallback functionality that must work even when Conditional Access policies or similar restrictions would block delegated access. For example, CIPP uses `-AsApp` for certain Conditional Access actions so an admin can recover from a misconfigured policy that locks them out of the tenant.

If none of these conditions apply, use delegated (the default). Do not add `-AsApp` "just in case."

## Scopes

Each API service has its own scope and therefore its own token:

| Service | Scope | Used by |
|---------|-------|---------|
| Microsoft Graph | `https://graph.microsoft.com/.default` | Default when no `-scope` specified |
| Exchange Online (EWS) | `https://outlook.office365.com/.default` | `New-ExoRequest`, auto-detected by `New-GraphGetRequest` for `outlook.office365.com` URIs |
| Outlook Cloud Settings | `https://outlook.office.com/.default` | `Set-CIPPSignature` (substrate.office.com) |
| Partner Center (app) | `https://api.partnercenter.microsoft.com/.default` | CPV consent, webhooks, tenant onboarding |
| Partner Center (delegated) | `https://api.partnercenter.microsoft.com/user_impersonation` | Autopilot device batches, Azure subscriptions, tenant offboarding |
| Teams/Skype | `48ac35b8-9aa8-4d74-927d-1f4a14a0b239/.default` | `New-TeamsRequest` |
| Office Management API | `https://manage.office.com/.default` | Audit log subscriptions, content bundles |
| Office Reports | `https://reports.office.com/.default` | Graph reports, Copilot readiness data |
| M365 Admin Portal | `https://admin.microsoft.com/.default` | License overview, self-service license policies |
| MDE (Defender for Endpoint) | `https://api.securitycenter.microsoft.com/.default` | TVM vulnerabilities |
| Self-Service Licensing | `aeb86249-8ea3-49e2-900b-54cc8e308f85/.default` | `licensing.m365.microsoft.com` self-service purchase policies |

Different scopes = different tokens. A single function call may internally use multiple tokens (e.g., `New-TeamsRequest` acquires both Teams and Graph tokens).

> **Note**: Partner Center has two scope variants. Use `.default` for app-level operations (webhooks, CPV consent). Use `user_impersonation` for delegated partner operations (device batches, subscriptions).

## Tenant types

### GDAP tenants (most common)

Partner's refresh token + CPV consent. Access is scoped by GDAP role assignments.

- GDAP (Granular Delegated Admin Privileges) controls what roles/permissions the partner has
- CPV consent (`Set-CIPPCPVConsent`) must be applied before GDAP roles work
- `Get-GraphToken` uses the partner's shared `$env:RefreshToken`

### Direct tenants

Customer provides their own refresh token, stored in Key Vault per-tenant (keyed by `customerId`).

- Identified by `delegatedPrivilegeStatus eq 'directTenant'` in the `Tenants` table
- `Get-GraphToken` lazy-loads the tenant-specific refresh token from Key Vault on first use
- Token is cached in an environment variable `$env:{customerId}` for subsequent calls in the same runspace

## Token caching

Tokens are cached in `[CIPP.CIPPTokenCache]` — a process-wide `ConcurrentDictionary` backed by a static .NET class in `Shared/CIPPSharp/CIPPRestClient.cs`.

- **Process-wide**: Shared across all runspaces in the worker process (unlike the old `$script:AccessTokens` which was per-runspace)
- **Cache key**: Built via `[CIPP.CIPPTokenCache]::BuildKey($tenantid, $scope, $asApp, $clientId, $grantType)`
- **Expiry-aware**: `Lookup()` accepts a buffer (seconds) and returns `$false` for expired or soon-to-expire tokens
- **Auto-refresh**: Expired tokens trigger automatic re-acquisition — no manual refresh needed
- **Skip cache**: Pass `-SkipCache $true` to force a fresh token (rare, for debugging)

## Error tracking

`Get-GraphToken` tracks consecutive failures per tenant:

| Field | Purpose |
|-------|---------|
| `GraphErrorCount` | Incremented on each token failure |
| `LastGraphError` | Error message from the last failure |
| `LastGraphTokenError` | Token error detail |

Stored on the tenant entity in the `Tenants` table. This allows the UI to show which tenants have broken auth.

## API helper functions

All of these handle token acquisition internally via `Get-GraphToken`:

### Graph API

| Function | Purpose |
|----------|--------|
| `New-GraphGetRequest` | GET with automatic retry, pagination, and token management |
| `New-GraphPOSTRequest` | POST, PATCH, PUT, or DELETE with retry |
| `New-GraphBulkRequest` | Batch `$batch` requests (up to 20 per batch) |

### Exchange Online

| Function | Purpose |
|----------|--------|
| `New-ExoRequest` | Execute a single Exchange cmdlet remotely |
| `New-ExoBulkRequest` | Execute multiple Exchange cmdlets in parallel |

#### Anchor mailbox routing

Exchange Online uses the `X-AnchorMailbox` header to route requests to the correct backend server. `New-ExoRequest` **automatically sets this header to a system mailbox** when no explicit `-Anchor` is provided — no action needed for most calls.

- **Default (no `-Anchor`)**: Routes to a well-known system mailbox. This is correct for tenant-level operations (`Set-OrganizationConfig`, `*-TransportRule`, policy cmdlets, distribution groups, contacts, etc.) and also works for per-user cmdlets where `Identity` is passed via `-cmdParams`.
- **Explicit `-Anchor`**: Only needed when the Exchange backend requires routing to a specific user's mailbox — primarily `Get-MailboxFolderPermission` and similar folder-level operations. Pass the target UPN: `-Anchor $UserUPN`.
- **`-useSystemMailbox`**: This parameter exists on both `New-ExoRequest` and `New-ExoBulkRequest` but is **not required for default system mailbox routing** — `New-ExoRequest` already defaults to that. Existing code passes it inconsistently. New code can omit it unless you need to force a specific anchor for an edge case (some Exchange cmdlets have obscure routing requirements from Microsoft's side).

### Teams

| Function | Purpose |
|----------|--------|
| `New-TeamsRequest` | Execute Teams/Skype cmdlets remotely |

Check function signatures (`Get-Help <FunctionName>`) for current parameter details.

## Developer rules

- **Never call `Get-GraphToken` directly** — the API helpers handle token acquisition internally
- **Always pass `-tenantid`** — without it, the call targets the partner tenant, not the customer
- **Do not hardcode secrets** — all credentials come from Key Vault via `Get-CIPPAuthentication`
- **Backtick-escape `$` in Graph OData URIs**: `` `$top ``, `` `$select ``, `` `$filter ``
- **Use `-AsApp $true` only when justified** — see the "Token modes → App-only" section above for the three valid reasons. Default to delegated.
- **Do not manually refresh tokens** — expiry and re-acquisition are handled automatically
- **Different services need different scopes** — Graph, Exchange, and Partner Center each have separate token flows
