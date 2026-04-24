# Missing CIPP Caches for CISA Tests

This document lists the caches that need to be created to support the remaining CISA tests that cannot currently be implemented.

## ✅ Implemented Cache Functions

### 1. ✅ CASMailbox Cache
**Required For:**
- ✅ MS.EXO.5.1 - SMTP Authentication

**Status**: ✅ IMPLEMENTED in Set-CIPPDBCacheCASMailbox.ps1

---

### 2. ✅ ExoSharingPolicy Cache
**Required For:**
- ✅ MS.EXO.6.1 - Contact Sharing
- ✅ MS.EXO.6.2 - Calendar Sharing

**Status**: ✅ IMPLEMENTED in Set-CIPPDBCacheExoSharingPolicy.ps1

---

### 3. ✅ ExoAdminAuditLogConfig Cache
**Required For:**
- ✅ MS.EXO.17.1 - Audit Log
- ✅ MS.EXO.17.3 - Audit Log Retention

**Status**: ✅ IMPLEMENTED in Set-CIPPDBCacheExoAdminAuditLogConfig.ps1

---

### 4. ✅ ExoPresetSecurityPolicy Cache
**Required For:**
- ✅ MS.EXO.11.1 - Impersonation
- ✅ MS.EXO.11.2 - Impersonation Tips
- ✅ MS.EXO.11.3 - Mailbox Intelligence

**Status**: ✅ IMPLEMENTED in Set-CIPPDBCacheExoPresetSecurityPolicy.ps1

---

### 5. ✅ ExoTenantAllowBlockList Cache
**Required For:**
- ✅ MS.EXO.12.1 - Anti-Spam Allow List

**Status**: ✅ IMPLEMENTED in Set-CIPPDBCacheExoTenantAllowBlockList.ps1

---

## Required New Cache Functions
**Required For:**
- MS.EXO.8.1 - DLP Solution
- MS.EXO.8.2 - DLP PII
- MS.EXO.8.4 - DLP Baseline Rules

**SecurityCompliance Command:**
```powershell
Get-DlpCompliancePolicy | Select-Object Name, Enabled, Mode
Get-DlpComplianceRule | Select-Object Name, ParentPolicyName, ContentContainsSensitiveInformation, Disabled
```
1
**Cache Function Names:**
- `Set-CIPPDBCacheSccDlpPolicy`
- `Set-CIPPDBCacheSccDlpRule`

**Properties Needed:**
- Policy: Name, Enabled, Mode
- Rule: Name, ParentPolicyName, ContentContainsSensitiveInformation, Disabled

**Note:** Requires SecurityCompliance PowerShell connection

---

### 2. SecurityCompliance ProtectionAlert Cache
**Required For:**
- MS.EXO.16.1 - Alerts

**SecurityCompliance Command:**
```powershell
Get-ProtectionAlert | Select-Object Name, Disabled
```

**Cache Function Name:** `Set-CIPPDBCacheSccProtectionAlert`

**Properties Needed:**
- Name
- Disabled

**Note:** Requires SecurityCompliance PowerShell connection

---

### 3. SecurityCompliance ActivityAlert Cache
**Required For:**
- MS.EXO.16.2 - Alert SIEM

**SecurityCompliance Command:**
```powershell
Get-ActivityAlert | Select-Object Name, Disabled, NotificationEnabled, Type
```

**Cache Function Name:** `Set-CIPPDBCacheSccActivityAlert`

**Properties Needed:**
- Name
- Disabled
- NotificationEnabled
- Type

**Note:** Requires SecurityCompliance PowerShell connection

---

## DNS-Based Tests (Cannot Be Cached)

These tests require external DNS lookups and cannot be implemented with cached Exchange data:

### MS.EXO.2.1 - SPF Restriction
**Requires:** DNS TXT record lookup for SPF
**Query:** `nslookup -type=txt <domain>`

### MS.EXO.2.2 - SPF Directive
**Requires:** DNS TXT record parsing for SPF policy
**Query:** Parse SPF record for `~all` or `-all`

### MS.EXO.4.1 - DMARC Record Exists
**Requires:** DNS TXT record lookup for DMARC
**Query:** `nslookup -type=txt _dmarc.<domain>`

### MS.EXO.4.2 - DMARC Reject Policy
**Requires:** DNS TXT record parsing for DMARC policy
**Query:** Parse DMARC record for `p=reject` or `p=quarantine`

### MS.EXO.4.3 - DMARC Aggregate Reports
**Requires:** DNS TXT record parsing for DMARC rua tags
**Query:** Parse DMARC record for `rua=` email addresses

### MS.EXO.4.4 - DMARC Reports
**Requires:** DNS TXT record parsing for DMARC report configuration
**Query:** Parse DMARC record for report targets

### MS.EXO.7.1 - External Sender Warning
**Requires:** ExoOrganizationConfig.ExternalInOutlook property
**Note:** May already be in ExoOrganizationConfig cache - needs verification

### MS.EXO.13.1 - Mailbox Auditing
**Requires:** ExoOrganizationConfig.AuditDisabled property
**Note:** May already be in ExoOrganizationConfig cache - needs verification

## Manual Assessment Tests (Cannot Be Automated)

### MS.EXO.8.3 - DLP Alternate Solution
**Reason:** Requires manual assessment of 3rd party DLP solutions

### MS.EXO.9.4 - Email Filter Alternative
**Reason:** Requires manual assessment of 3rd party email filtering solutions

### MS.EXO.14.4 - Spam Alternative Solution
**Reason:** Requires manual assessment of 3rd party anti-spam solutions

### MS.EXO.17.2 - Audit Log Premium
**Reason:** Requires license validation and advanced audit policy checks beyond cached data

---

## Implementation Priority

### High Priority (Core Security Controls):
1. CASMailbox - SMTP Auth control
2. ExoAdminAuditLogConfig - Audit logging
3. ExoTenantAllowBlockList - Allow list bypass prevention

### Medium Priority (DLP and Alerts):
4. SecurityCompliance DLP caches - Data loss prevention
5. SecurityCompliance Alert caches - Security monitoring

### Low Priority (Advanced Features):
6. ExoSharingPolicy - External sharing controls
7. ExoPresetSecurityPolicy - Preset security policies

---

## Notes on Implementation

1. **Graph API Alternative**: Some Exchange Online cmdlets may have equivalent Graph API endpoints that could be used instead.

## Summary

- **New Caches Required**: 8 cache functions
- **DNS Tests**: 6 tests (architectural limitation)
- **Manual Tests**: 4 tests (cannot be automated)
- **Implementable After New Caches**: 15 additional tests
- **Current Implementation**: 13 tests
- **Total Possible with New Caches**: 28 tests (68% coverage)
