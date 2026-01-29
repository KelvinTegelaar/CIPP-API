function Invoke-CIPPStandardDisableGuests {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableGuests
    .SYNOPSIS
        (Label) Disable Guest accounts that have not logged on for a number of days
    .DESCRIPTION
        (Helptext) Blocks login for guest users that have not logged in for a number of days
        (DocsDescription) Blocks login for guest users that have not logged in for a number of days
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Automatically disables external guest accounts that haven't been used for a number of days, reducing security risks from dormant accounts while maintaining access for active external collaborators. This helps maintain a clean user directory and reduces potential attack vectors.
        ADDEDCOMPONENT
            {"type":"number","name":"standards.DisableGuests.days","required":true,"defaultValue":90,"label":"Days of inactivity"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2022-10-20
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableGuests' -TenantFilter $Tenant -RequiredCapabilities @('AAD_PREMIUM', 'AAD_PREMIUM_P2')

    if ($TestResult -eq $false) {
        #writing to each item that the license is not present.
        foreach ($Template in $settings.TemplateList) {
            Set-CIPPStandardsCompareField -FieldName 'standards.DisableGuests' -FieldValue 'This tenant does not have the required license for this standard.' -Tenant $Tenant
        }
        return $true
    } #we're done.

    $checkDays = if ($Settings.days) { $Settings.days } else { 90 } # Default to 90 days if not set. Pre v8.5.0 compatibility
    $Days = (Get-Date).AddDays(-$checkDays).ToUniversalTime()
    $AuditLookup = (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')

    try {
        $AllUsers = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'

        $GraphRequest = $AllUsers | Where-Object {
            $_.userType -eq 'Guest' -and
            $_.accountEnabled -eq $true -and
            ($null -ne $_.createdDateTime -and [DateTime]$_.createdDateTime -le $Days) -and
            ($null -eq $_.signInActivity -or $null -eq $_.signInActivity.lastSuccessfulSignInDateTime -or [DateTime]$_.signInActivity.lastSuccessfulSignInDateTime -le $Days)
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableGuests state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $AuditResults = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Enable account' and activityDateTime ge $AuditLookup" -scope 'https://graph.microsoft.com/.default' -tenantid $Tenant
    $RecentlyReactivatedUsers = @(foreach ($AuditEntry in $AuditResults) { $AuditEntry.targetResources[0].id }) | Select-Object -Unique

    $GraphRequest = $GraphRequest | Where-Object { -not ($RecentlyReactivatedUsers -contains $_.id) }

    if ($Settings.remediate -eq $true) {
        if ($GraphRequest.Count -gt 0) {
            $int = 0
            $BulkRequests = foreach ($guest in $GraphRequest) {
                @{
                    id        = $int++
                    method    = 'PATCH'
                    url       = "users/$($guest.id)"
                    body      = @{ accountEnabled = $false }
                    'headers' = @{
                        'Content-Type' = 'application/json'
                    }
                }
            }

            try {
                $BulkResults = New-GraphBulkRequest -tenantid $tenant -Requests @($BulkRequests)

                for ($i = 0; $i -lt $BulkResults.Count; $i++) {
                    $result = $BulkResults[$i]
                    $guest = $GraphRequest[$i]

                    if ($result.status -eq 200 -or $result.status -eq 204) {
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabled guest $($guest.UserPrincipalName) ($($guest.id)). Last sign-in: $($guest.signInActivity.lastSuccessfulSignInDateTime)" -sev Info
                    } else {
                        $errorMsg = if ($result.body.error.message) { $result.body.error.message } else { "Unknown error (Status: $($result.status))" }
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable guest $($guest.UserPrincipalName) ($($guest.id)): $errorMsg" -sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to process bulk disable guests request: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }

            # Refresh user cache after remediation
            try {
                Set-CIPPDBCacheUsers -TenantFilter $Tenant
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to refresh user cache after remediation: $($_.Exception.Message)" -sev Warning
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "No guests accounts with a login longer than $checkDays days ago." -sev Info
        }
    }
    if ($Settings.alert -eq $true) {

        if ($GraphRequest.Count -gt 0) {
            $Filtered = $GraphRequest | Select-Object -Property UserPrincipalName, id, signInActivity, mail, userType, accountEnabled, externalUserState
            Write-StandardsAlert -message "Guests accounts with a login longer than 90 days ago: $($GraphRequest.count)" -object $Filtered -tenant $tenant -standardName 'DisableGuests' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Guests accounts with a login longer than $checkDays days ago: $($GraphRequest.count)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "No guests accounts with a login longer than $checkDays days ago." -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        $Filtered = $GraphRequest | Select-Object -Property UserPrincipalName, id, signInActivity, mail, userType, accountEnabled

        $CurrentValue = [PSCustomObject]@{
            GuestsDisabledAfterDays      = $checkDays
            GuestsDisabledAccountCount   = $Filtered.Count
            GuestsDisabledAccountDetails = @($Filtered)
        }

        $ExpectedValue = [PSCustomObject]@{
            GuestsDisabledAfterDays      = $checkDays
            GuestsDisabledAccountCount   = 0
            GuestsDisabledAccountDetails = @()
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableGuests' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableGuests' -FieldValue $Filtered -StoreAs json -Tenant $tenant
    }
}
