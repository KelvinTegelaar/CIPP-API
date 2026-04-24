---
applyTo: "Modules/CIPPStandards/Public/Standards/**"
description: "Use when creating, modifying, or reviewing CIPP standard functions (Invoke-CIPPStandard*). Contains scaffolding patterns, the three action modes (remediate/alert/report), $Settings conventions, API call patterns, and frontend JSON payloads."
---

# CIPP Standard Functions

Standard functions live in `Modules/CIPPStandards/Public/Standards/` and are auto-loaded by the CIPPStandards module. No manifest changes needed.

## Naming

- File: `Invoke-CIPPStandard<Name>.ps1`
- Function name must match the filename exactly.
- The frontend references it as `standards.<Name>` (e.g., `Invoke-CIPPStandardMailContacts` → `standards.MailContacts`).

## Skeleton

Every standard follows this structure:

```powershell
function Invoke-CIPPStandard<Name> {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) <Name>
    .SYNOPSIS
        (Label) Human-readable label shown in UI
    .DESCRIPTION
        (Helptext) Short description for the UI tooltip
        (DocsDescription) Longer description for documentation
    .NOTES
        CAT
            Exchange Standards | Entra (AAD) Standards | Global Standards | Templates | Defender Standards | Teams Standards | SharePoint Standards
            (check existing standards if a new category has been added)
        TAG
            "CIS M365 5.0 (X.X.X)"
        EXECUTIVETEXT
            Business-level summary of what this standard does and why
        ADDEDCOMPONENT
            [{"type":"textField","name":"standards.<Name>.FieldName","label":"Field Label","required":false}]
        IMPACT
            Low Impact | Medium Impact | High Impact
        ADDEDDATE
            YYYY-MM-DD
        POWERSHELLEQUIVALENT
            Set-SomeCommand or Graph endpoint
        RECOMMENDEDBY
            "CIS" | "CIPP"
        MULTIPLE
            True
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        REQUIREDCAPABILITIES
            "CAPABILITY_1"
            "CAPABILITY_2"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param(
        $Tenant,
        $Settings
    )

    # 1. License gate (if the data source requires a specific SKU)
    $TestResult = Test-CIPPStandardLicense -StandardName '<Name>' -TenantFilter $Tenant `
        -RequiredCapabilities @('CAPABILITY_1', 'CAPABILITY_2')
    if ($TestResult -eq $false) { return $true }

    # 2. Get current state
    #    Prefer cached data via New-CIPPDbRequest over live API calls.
    #    See .github/instructions/cippdb.instructions.md for available types and query patterns.
    try {
        $CurrentState = New-CIPPDbRequest -TenantFilter $Tenant -Type 'TypeName'
        # Or for data not in the cache:
        # $CurrentState = New-GraphGetRequest -uri '...' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Could not get state: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    # 3. Determine compliance
    $StateIsCorrect = <compare current state to desired state>

    # 4. Remediate
    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Already configured correctly.' -sev Info
        } else {
            try {
                <apply desired configuration>
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Successfully remediated.' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    # 5. Alert
    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Compliant.' -sev Info
        } else {
            Write-StandardsAlert -message 'Not compliant: <reason>' -object $CurrentState `
                -tenant $Tenant -standardName '<Name>' -standardId $Settings.standardId
        }
    }

    # 6. Report
    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.<Name>' `
            -CurrentValue @{ property = $CurrentState.property } `
            -ExpectedValue @{ property = $DesiredValue } `
            -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName '<Name>' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
```

### Required elements

| Element | Rule |
|---------|------|
| `.FUNCTIONALITY Internal` | Must be present — the standards engine uses this for discovery. |
| `.COMPONENT (APIName) <Name>` | Database key for the standard. Must match the function suffix. |
| `.SYNOPSIS (Label)` | Display name in the UI. |
| `.NOTES` block | Controls UI rendering: category, tags, impact level, added components, etc. |
| `$Tenant` parameter | Tenant identifier passed by the orchestrator. |
| `$Settings` parameter | Normalized settings object containing action modes and custom fields. |
| Three action modes | Every standard must handle `remediate`, `alert`, and `report` independently. |

## The `$Settings` object

The orchestrator normalizes tenant-specific configuration into `$Settings`. It always has these core properties:

| Property | Type | Purpose |
|----------|------|---------|
| `remediate` | `[bool]` | Execute fix/deployment logic |
| `alert` | `[bool]` | Send alerts if noncompliant |
| `report` | `[bool]` | Generate compliance data for dashboards |
| `standardId` | `[string]` | Unique ID for this standard instance |

Custom properties come from the `ADDEDCOMPONENT` metadata, e.g., `standards.MailContacts.GeneralContact` becomes `$Settings.GeneralContact`.

### Value extraction for autocomplete fields

UI autocomplete fields may wrap the value in a `.value` property. Always handle both:

```powershell
$DesiredValue = $Settings.SomeField.value ?? $Settings.SomeField
```

With fallback to current state:

```powershell
$DesiredValue = $Settings.AutoAdmittedUsers.value ?? $Settings.AutoAdmittedUsers ?? $CurrentState.AutoAdmittedUsers
```

### Validating required input

```powershell
if ([string]::IsNullOrWhiteSpace($Settings.RequiredField)) {
    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'RequiredField is empty, skipping.' -sev Error
    return
}
```

## The three action modes

### Remediate (`$Settings.remediate -eq $true`)

Detect noncompliance and fix it. Always check current state first to avoid unnecessary writes.

```powershell
if ($Settings.remediate -eq $true) {
    if ($StateIsCorrect) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Already configured.' -sev Info
    } else {
        try {
            # Apply configuration change
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Remediated successfully.' -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }
}
```

### Alert (`$Settings.alert -eq $true`)

Notify admins of noncompliance without changing anything. Use `Write-StandardsAlert`.

```powershell
if ($Settings.alert -eq $true) {
    if ($StateIsCorrect) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Compliant.' -sev Info
    } else {
        Write-StandardsAlert -message 'Description of noncompliance' `
            -object ($CurrentState | Select-Object RelevantProperty1, RelevantProperty2) `
            -tenant $Tenant -standardName '<Name>' -standardId $Settings.standardId
    }
}
```

### Report (`$Settings.report -eq $true`)

Store comparison data for dashboards. Always supply both current and expected values.

```powershell
if ($Settings.report -eq $true) {
    Set-CIPPStandardsCompareField -FieldName 'standards.<Name>' `
        -CurrentValue @{ property = $CurrentState.property } `
        -ExpectedValue @{ property = $DesiredValue } `
        -TenantFilter $Tenant

    Add-CIPPBPAField -FieldName '<Name>' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
}
```

For complex data:

```powershell
Add-CIPPBPAField -FieldName '<Name>Details' -FieldValue $ComplexObject -StoreAs json -Tenant $Tenant
```

## License gating

Gate early using `Test-CIPPStandardLicense`. Never inspect raw SKU IDs.

```powershell
$TestResult = Test-CIPPStandardLicense -StandardName '<Name>' -TenantFilter $Tenant `
    -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE')
if ($TestResult -eq $false) { return $true }
```

The function checks tenant capabilities, logs if missing, and automatically sets the `Set-CIPPStandardsCompareField` with `LicenseAvailable = $false`.

Reference existing standards in the same domain for common capability strings. The `Test-CIPPStandardLicense` function source documents the capability matching logic.

## API call patterns

All API helpers handle token acquisition automatically. For scope selection, `-AsApp` usage, and available scopes, see `.github/instructions/auth-model.instructions.md`.

### Graph — GET

```powershell
$Data = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/...' -tenantid $Tenant
```

### Graph — POST/PATCH

```powershell
$Body = @{ property = $Value } | ConvertTo-Json -Compress -Depth 10
New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/...' `
    -Type PATCH -Body $Body -ContentType 'application/json'
```

### Exchange — single command

```powershell
$CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-HostedOutboundSpamFilterPolicy' `
    -cmdParams @{ Identity = 'Default' }
```

### Exchange — bulk operations

```powershell
$Request = @($ItemsToFix | ForEach-Object {
    @{
        CmdletInput = @{
            CmdletName = 'Set-Mailbox'
            Parameters = @{
                Identity              = $_.UserPrincipalName
                LitigationHoldEnabled = $true
            }
        }
    }
})
$BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($Request)

foreach ($Result in $BatchResults) {
    if ($Result.error) {
        $ErrorMessage = Get-NormalizedError -Message $Result.error
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed for $($Result.target): $ErrorMessage" -sev Error
    }
}
```

### Teams

```powershell
# Query
$CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsMeetingPolicy' `
    -CmdParams @{ Identity = 'Global' }

# Modify
New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsMeetingPolicy' `
    -CmdParams @{ Identity = 'Global'; AllowAnonymousUsersToJoinMeeting = $false }
```

## Logging

```powershell
# Success
Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Action completed.' -sev Info

# Error (preferred — includes full exception data)
$ErrorMessage = Get-CippException -Exception $_
Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage

# Error (legacy — still used in older standards)
$ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed: $ErrorMessage" -sev Error
```

Use `Get-CippException` for new standards. `Get-NormalizedError` is legacy but still acceptable.

## `.NOTES` metadata reference

The comment-based help `.NOTES` block drives the frontend UI. Each field maps to the standards JSON:

| Notes field | JSON key | Description |
|-------------|----------|-------------|
| `CAT` | `cat` | Category tab in the UI (see valid values below) |
| `TAG` | `tag` | Compliance framework tags (CIS, NIST, etc.) |
| `EXECUTIVETEXT` | `executiveText` | Business-level summary |
| `ADDEDCOMPONENT` | `addedComponent` | JSON array of UI form fields |
| `IMPACT` | `impact` | Exactly one of: `Low Impact`, `Medium Impact`, `High Impact` |
| `ADDEDDATE` | `addedDate` | When the standard was added (YYYY-MM-DD) |
| `POWERSHELLEQUIVALENT` | `powershellEquivalent` | Native cmdlet or Graph endpoint |
| `RECOMMENDEDBY` | `recommendedBy` | `"CIS"`, `"CIPP"`, etc. |
| `MULTIPLE` | `multiple` | `True` for template-based standards (can have multiple instances) |
| `DISABLEDFEATURES` | `disabledFeatures` | JSON object disabling specific action modes |
| `REQUIREDCAPABILITIES` | *(discovery only)* | One capability string per line; parsed for standards metadata/JSON generation. The explicit `Test-CIPPStandardLicense` call in the function body still performs the actual runtime license check. |
| `UPDATECOMMENTBLOCK` | *(tooling only)* | Always include with the literal value `Run the Tools\Update-StandardsComments.ps1 script to update this comment block`. Signals the comment-update tooling to regenerate this block. |

### Valid CAT values

These are the exact category strings the frontend recognizes. Using any other value will break UI categorization:

- `Exchange Standards`
- `Entra (AAD) Standards`
- `Global Standards`
- `Templates`
- `Defender Standards`
- `Teams Standards`
- `SharePoint Standards`
- `Intune Standards`

### ADDEDCOMPONENT field types

```json
[
  {"type": "textField",    "name": "standards.<Name>.FieldName",  "label": "Label", "required": false},
  {"type": "switch",       "name": "standards.<Name>.Toggle",     "label": "Enable Feature"},
  {"type": "autoComplete", "name": "standards.<Name>.Selection",  "label": "Choose", "multiple": true,
   "api": {"url": "/api/ListGraphRequest", "data": {"Endpoint": "..."}}},
  {"type": "number",       "name": "standards.<Name>.Days",       "label": "Days", "default": 30},
  {"type": "radio",        "name": "standards.<Name>.Mode",       "label": "Mode",
   "options": [{"label": "Audit", "value": "audit"}, {"label": "Block", "value": "block"}]}
]
```

The `name` prefix `standards.<Name>.` is stripped — `standards.MailContacts.GeneralContact` becomes `$Settings.GeneralContact`.

## Frontend JSON payload

When creating a new standard, the frontend also needs a JSON entry. Include it in the PR description so a frontend engineer can add it:

```json
{
  "name": "standards.<Name>",
  "cat": "Exchange Standards",
  "tag": [],
  "helpText": "Short description",
  "docsDescription": "Longer documentation description",
  "executiveText": "Business-level summary",
  "addedComponent": [],
  "label": "Human-readable label",
  "impact": "Low Impact",
  "impactColour": "info",
  "addedDate": "2026-04-09",
  "powershellEquivalent": "Set-SomeCommand",
  "recommendedBy": []
}
```

Impact colour mapping: `Low Impact` → `info`, `Medium Impact` → `warning`, `High Impact` → `danger`.

## Checklist for new standards

1. Create `Modules/CIPPStandards/Public/Standards/Invoke-CIPPStandard<Name>.ps1`
2. Include the full `.NOTES` metadata block (CAT, TAG, IMPACT, ADDEDCOMPONENT, etc.)
3. Implement all three modes: remediate, alert, report
4. Add license gating if the data source requires a specific SKU
5. Use `Get-CippException` for error handling in new code
6. Prepare the frontend JSON payload for the PR description
7. No changes needed to module manifests or registration code
