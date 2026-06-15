function Invoke-CIPPStandardAppManagementPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AppManagementPolicy
    .SYNOPSIS
        (Label) Set Default App Management Policy
    .DESCRIPTION
        (Helptext) Configures the default app management policy to control application and service principal credential restrictions such as password and key credential lifetimes.
        (DocsDescription) Configures the default app management policy to control application and service principal credential restrictions. This includes password addition restrictions, custom password addition, symmetric key addition, and credential lifetime limits for both applications and service principals.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Enforces credential restrictions on application registrations and service principals to limit how secrets and certificates are created and how long they remain valid. This reduces the risk of long-lived or unmanaged credentials being used to access your tenant.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"required":false,"name":"standards.AppManagementPolicy.passwordCredentialsPasswordAddition","label":"Disable Password Addition","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
            {"type":"autoComplete","multiple":false,"creatable":false,"required":false,"name":"standards.AppManagementPolicy.passwordCredentialsCustomPasswordAddition","label":"Disable Custom Password","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
            {"type":"number","required":false,"name":"standards.AppManagementPolicy.passwordCredentialsMaxLifetime","label":"Password Credentials Max Lifetime (Days)"}
            {"type":"number","required":false,"name":"standards.AppManagementPolicy.keyCredentialsMaxLifetime","label":"Key Credentials Max Lifetime (Days)"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-03-13
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    # Get current app management policy
    try {
        $CurrentPolicy = New-GraphGetRequest -Uri 'https://graph.microsoft.com/v1.0/policies/defaultAppManagementPolicy' -tenantid $Tenant -AsApp $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to get App Management Policy. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    # Unwrap autoComplete values - frontend sends {label, value} objects, extract the string
    $passwordAdditionState = [string]$Settings.passwordCredentialsPasswordAddition.value
    $customPasswordState = [string]$Settings.passwordCredentialsCustomPasswordAddition.value
    $passwordMaxLifetimeDays = $Settings.passwordCredentialsMaxLifetime
    $keyMaxLifetimeDays = $Settings.keyCredentialsMaxLifetime

    # Convert user-entered days to ISO 8601 duration format (P<n>D)
    $passwordMaxLifetimeISO = if (-not [string]::IsNullOrWhiteSpace($passwordMaxLifetimeDays)) { "P${passwordMaxLifetimeDays}D" } else { $null }
    $keyMaxLifetimeISO = if (-not [string]::IsNullOrWhiteSpace($keyMaxLifetimeDays)) { "P${keyMaxLifetimeDays}D" } else { $null }

    # Build desired password credential restrictions
    $desiredPasswordCredentials = [System.Collections.Generic.List[object]]::new()

    # Password addition + symmetric key addition (mirrors password addition)
    if (-not [string]::IsNullOrWhiteSpace($passwordAdditionState)) {
        $desiredPasswordCredentials.Add([ordered]@{
            restrictionType                     = 'passwordAddition'
            state                               = $passwordAdditionState
            maxLifetime                         = $null
            restrictForAppsCreatedAfterDateTime = '0001-01-01T00:00:00Z'
        })
        $desiredPasswordCredentials.Add([ordered]@{
            restrictionType                     = 'symmetricKeyAddition'
            state                               = $passwordAdditionState
            maxLifetime                         = $null
            restrictForAppsCreatedAfterDateTime = '0001-01-01T00:00:00Z'
        })
    }

    # Custom password
    if (-not [string]::IsNullOrWhiteSpace($customPasswordState)) {
        $desiredPasswordCredentials.Add([ordered]@{
            restrictionType                     = 'customPasswordAddition'
            state                               = $customPasswordState
            maxLifetime                         = $null
            restrictForAppsCreatedAfterDateTime = '0001-01-01T00:00:00Z'
        })
    }

    # Password credential max lifetime
    if ($passwordMaxLifetimeISO) {
        $desiredPasswordCredentials.Add([ordered]@{
            restrictionType                     = 'passwordLifetime'
            state                               = 'enabled'
            maxLifetime                         = $passwordMaxLifetimeISO
            restrictForAppsCreatedAfterDateTime = '0001-01-01T00:00:00Z'
        })
    }

    # Symmetric key credential max lifetime
    if ($keyMaxLifetimeISO) {
        $desiredPasswordCredentials.Add([ordered]@{
            restrictionType                     = 'symmetricKeyLifetime'
            state                               = 'enabled'
            maxLifetime                         = $keyMaxLifetimeISO
            restrictForAppsCreatedAfterDateTime = '0001-01-01T00:00:00Z'
        })
    }

    # Key credentials (asymmetric key lifetime)
    $desiredKeyCredentials = @(
        if ($keyMaxLifetimeISO) {
            [ordered]@{
                restrictionType                     = 'asymmetricKeyLifetime'
                state                               = 'enabled'
                maxLifetime                         = $keyMaxLifetimeISO
                restrictForAppsCreatedAfterDateTime = '0001-01-01T00:00:00Z'
            }
        }
    )

    if ($desiredPasswordCredentials.Count -eq 0 -and $desiredKeyCredentials.Count -eq 0) {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'AppManagementPolicy: No valid restriction settings were configured.' -Sev Info
        return
    }

    # Sort desired restrictions by restrictionType so order matches Graph API responses
    # Use script block because items are hashtables, not PSCustomObjects
    $sortedDesiredPasswordCredentials = @($desiredPasswordCredentials | Sort-Object { $_.restrictionType })
    $sortedDesiredKeyCredentials = @($desiredKeyCredentials | Sort-Object { $_.restrictionType })

    $desiredState = [PSCustomObject]@{
        isEnabled                   = $true
        applicationRestrictions     = [PSCustomObject]@{
            passwordCredentials = $sortedDesiredPasswordCredentials
            keyCredentials      = $sortedDesiredKeyCredentials
        }
        servicePrincipalRestrictions = [PSCustomObject]@{
            passwordCredentials = $sortedDesiredPasswordCredentials
            keyCredentials      = $sortedDesiredKeyCredentials
        }
    }

    # Sort current policy arrays the same way for consistent comparison
    $CurrentValue = [PSCustomObject]@{
        isEnabled                   = [bool]$CurrentPolicy.isEnabled
        applicationRestrictions     = [PSCustomObject]@{
            passwordCredentials = @($CurrentPolicy.applicationRestrictions.passwordCredentials | Sort-Object -Property restrictionType)
            keyCredentials      = @($CurrentPolicy.applicationRestrictions.keyCredentials | Sort-Object -Property restrictionType)
        }
        servicePrincipalRestrictions = [PSCustomObject]@{
            passwordCredentials = @($CurrentPolicy.servicePrincipalRestrictions.passwordCredentials | Sort-Object -Property restrictionType)
            keyCredentials      = @($CurrentPolicy.servicePrincipalRestrictions.keyCredentials | Sort-Object -Property restrictionType)
        }
    }

    $CurrentJson = $CurrentValue | ConvertTo-Json -Depth 10 -Compress
    $ExpectedJson = $desiredState | ConvertTo-Json -Depth 10 -Compress
    $StateIsCorrect = $CurrentJson -eq $ExpectedJson

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'App Management Policy is already in the desired state.' -Sev Info
        } else {
            try {
                $GraphRequest = @{
                    tenantID    = $Tenant
                    uri         = 'https://graph.microsoft.com/v1.0/policies/defaultAppManagementPolicy'
                    AsApp       = $true
                    Type        = 'PATCH'
                    ContentType = 'application/json; charset=utf-8'
                    Body        = $desiredState | ConvertTo-Json -Depth 20 -Compress
                }

                $null = New-GraphPostRequest @GraphRequest
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Updated default app management policy.' -Sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to update default app management policy. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'App Management Policy is configured correctly.' -Sev Info
        } else {
            Write-StandardsAlert -message 'App Management Policy is not configured correctly.' -object $CurrentValue -tenant $Tenant -standardName 'AppManagementPolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'App Management Policy is not configured correctly.' -Sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.AppManagementPolicy' -CurrentValue $CurrentValue -ExpectedValue $desiredState -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'AppManagementPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
