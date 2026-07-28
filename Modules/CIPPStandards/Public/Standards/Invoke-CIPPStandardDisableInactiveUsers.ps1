function Invoke-CIPPStandardDisableInactiveUsers {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableInactiveUsers
    .SYNOPSIS
        (Label) Disable Member accounts that have not logged on for a number of days
    .DESCRIPTION
        (Helptext) Blocks login for cloud-only member users that have not signed in for a configurable number of days (minimum 30). Includes accounts that have never signed in when the account is older than the threshold. Hybrid (on-premises synced) users are skipped. Users without sign-in activity data are not disabled.
        (DocsDescription) Disables enabled Member user accounts after a defined period of inactivity (minimum 30 days), supporting CMMC IA.L2-3.5.6 / NIST SP 800-171 3.5.6. Inactivity is based on signInActivity.lastSuccessfulSignInDateTime. Accounts that have never signed in (signInActivity present but no successful sign-in) are included when createdDateTime is older than the threshold. Users missing signInActivity entirely are skipped so incomplete Graph data cannot cause accidental disables. Hybrid-synced (onPremisesSyncEnabled) users are skipped because Entra disable often will not stick. Recently re-enabled accounts (last 7 days) are also skipped. Values below 30 days are rejected at runtime.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CMMC (IA.L2-3.5.6)"
            "NIST SP 800-171 (3.5.6)"
        EXECUTIVETEXT
            Automatically disables unused employee accounts that have not signed in for a configured number of days, reducing risk from dormant accounts and supporting CMMC / NIST inactive-identifier requirements. Hybrid directory-synced accounts are left alone so on-premises identity remains the source of truth for those users.
        ADDEDCOMPONENT
            {"type":"number","name":"standards.DisableInactiveUsers.days","required":true,"defaultValue":180,"label":"Days of inactivity (minimum 30)","validators":{"min":{"value":30,"message":"Minimum value is 30"}}}
        IMPACT
            High Impact
        ADDEDDATE
            2026-07-22
        POWERSHELLEQUIVALENT
            Get-MgUser -Property SignInActivity & Update-MgUser -AccountEnabled $false
        RECOMMENDEDBY
            "CIPP"
            "CMMC"
        REQUIREDCAPABILITIES
            "AAD_PREMIUM"
            "AAD_PREMIUM_P2"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableInactiveUsers' -TenantFilter $Tenant -Preset Entra

    if ($TestResult -eq $false) {
        foreach ($Template in $Settings.TemplateList) {
            Set-CIPPStandardsCompareField -FieldName 'standards.DisableInactiveUsers' -FieldValue 'This tenant does not have the required license for this standard.' -Tenant $Tenant
        }
        return $true
    }

    $checkDays = if ($Settings.days) { [int]$Settings.days } else { 180 }
    if ($checkDays -lt 30) {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "DisableInactiveUsers: days ($checkDays) is below the minimum of 30 days. Skipping run to prevent mass user changes." -Sev Error
        return
    }
    $Days = (Get-Date).AddDays(-$checkDays).ToUniversalTime()
    $Lookup = $Days.ToString('o')
    $AuditLookup = (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=createdDateTime le $Lookup and userType eq 'Member' and accountEnabled eq true&`$select=id,userPrincipalName,displayName,signInActivity,mail,userType,accountEnabled,createdDateTime,onPremisesSyncEnabled" -scope 'https://graph.microsoft.com/.default' -tenantid $Tenant

        $InactiveUsers = foreach ($user in $GraphRequest) {
            if ($user.onPremisesSyncEnabled -eq $true) { continue }

            # Missing signInActivity means incomplete Graph data — do not treat as never signed in
            if (-not $user.signInActivity) { continue }

            if ($user.signInActivity.lastSuccessfulSignInDateTime) {
                $lastSignIn = [datetime]$user.signInActivity.lastSuccessfulSignInDateTime
                if ($lastSignIn.ToUniversalTime() -le $Days) {
                    $user | Add-Member -NotePropertyName 'EnrichedLastSignInDateTime' -NotePropertyValue $user.signInActivity.lastSuccessfulSignInDateTime -Force
                    $user | Add-Member -NotePropertyName 'NeverSignedIn' -NotePropertyValue $false -Force
                    $user
                }
            } else {
                # signInActivity present but no successful sign-in; createdDateTime already <= $Days via server-side filter
                $user | Add-Member -NotePropertyName 'EnrichedLastSignInDateTime' -NotePropertyValue $null -Force
                $user | Add-Member -NotePropertyName 'NeverSignedIn' -NotePropertyValue $true -Force
                $user
            }
        }
        $GraphRequest = @($InactiveUsers)
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableInactiveUsers state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $AuditResults = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Enable account' and activityDateTime ge $AuditLookup" -scope 'https://graph.microsoft.com/.default' -tenantid $Tenant
    $RecentlyReactivatedUsers = @(foreach ($AuditEntry in $AuditResults) { $AuditEntry.targetResources[0].id }) | Select-Object -Unique

    $GraphRequest = @($GraphRequest | Where-Object { -not ($RecentlyReactivatedUsers -contains $_.id) })

    if ($Settings.remediate -eq $true) {
        if ($GraphRequest.Count -gt 0) {
            $UpdateDB = $false
            $int = 0
            $BulkRequests = foreach ($user in $GraphRequest) {
                @{
                    id        = $int++
                    method    = 'PATCH'
                    url       = "users/$($user.id)"
                    body      = @{ accountEnabled = $false }
                    'headers' = @{
                        'Content-Type' = 'application/json'
                    }
                }
            }

            try {
                $BulkResults = New-GraphBulkRequest -tenantid $Tenant -Requests @($BulkRequests)

                for ($i = 0; $i -lt $BulkResults.Count; $i++) {
                    $result = $BulkResults[$i]
                    $user = $GraphRequest[$i]

                    if ($result.status -eq 200 -or $result.status -eq 204) {
                        $user.accountEnabled = $false
                        $UpdateDB = $true
                        $reason = if ($user.NeverSignedIn) {
                            "never signed in; account created $($user.createdDateTime)"
                        } else {
                            "last sign-in: $($user.EnrichedLastSignInDateTime)"
                        }
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Disabled inactive user $($user.userPrincipalName) ($($user.id)). Reason: $reason" -sev Info
                    } else {
                        $errorMsg = if ($result.body.error.message) { $result.body.error.message } else { "Unknown error (Status: $($result.status))" }
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to disable inactive user $($user.userPrincipalName) ($($user.id)): $errorMsg" -sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to process bulk disable inactive users request: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }

            if ($UpdateDB) {
                try {
                    Set-CIPPDBCacheUsers -TenantFilter $Tenant
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to refresh user cache after remediation: $($_.Exception.Message)" -sev Warning
                }
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "No member accounts inactive longer than $checkDays days - all cloud-only member accounts are already compliant." -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        $AlertUsers = @($GraphRequest | Where-Object { $_.accountEnabled })
        if ($AlertUsers.Count -gt 0) {
            $Filtered = $AlertUsers | Select-Object -Property userPrincipalName, id, displayName, signInActivity, EnrichedLastSignInDateTime, NeverSignedIn, mail, userType, accountEnabled, createdDateTime, onPremisesSyncEnabled
            $NeverSignedInCount = @($Filtered | Where-Object { $_.NeverSignedIn }).Count
            $StaleCount = $Filtered.Count - $NeverSignedInCount
            $AlertMessage = "Inactive member accounts found: $($AlertUsers.Count) total ($StaleCount inactive >$checkDays days, $NeverSignedInCount never signed in and older than $checkDays days)"
            Write-StandardsAlert -message $AlertMessage -object $Filtered -tenant $Tenant -standardName 'DisableInactiveUsers' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "No inactive member accounts found (threshold: $checkDays days)." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $Filtered = $GraphRequest | Where-Object { $_.accountEnabled } | Select-Object -Property userPrincipalName, id, displayName, signInActivity, EnrichedLastSignInDateTime, NeverSignedIn, mail, userType, accountEnabled, createdDateTime, onPremisesSyncEnabled
        $NeverSignedInUsers = @($Filtered | Where-Object { $_.NeverSignedIn })
        $StaleSignIns = @($Filtered | Where-Object { -not $_.NeverSignedIn })

        $CurrentValue = [PSCustomObject]@{
            UsersDisabledAfterDays      = $checkDays
            UsersDisabledAccountCount   = $Filtered.Count
            UsersStaleSignInCount       = $StaleSignIns.Count
            UsersNeverSignedInCount     = $NeverSignedInUsers.Count
            UsersDisabledAccountDetails = @($Filtered)
            UsersNeverSignedInDetails   = $NeverSignedInUsers
        }

        $ExpectedValue = [PSCustomObject]@{
            UsersDisabledAfterDays      = $checkDays
            UsersDisabledAccountCount   = 0
            UsersStaleSignInCount       = 0
            UsersNeverSignedInCount     = 0
            UsersDisabledAccountDetails = @()
            UsersNeverSignedInDetails   = @()
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableInactiveUsers' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableInactiveUsers' -FieldValue $Filtered -StoreAs json -Tenant $Tenant
    }
}
