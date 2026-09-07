function Invoke-CIPPStandardDisableGuests {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableGuests
    .SYNOPSIS
        (Label) Disable Guest accounts that have not logged on for a number of days
    .DESCRIPTION
        (Helptext) Blocks login for guest users whose most recent sign-in attempt, interactive or non-interactive, is older than the number of days. Guests that have never signed in are only included when 'Disable accounts that have not yet signed in' is enabled. Accounts an administrator re-enabled in the last 7 days are left alone.
        (DocsDescription) Blocks login for guest users whose most recent sign-in attempt, interactive or non-interactive, is older than the number of days. Guests that have never signed in are only included when 'Disable accounts that have not yet signed in' is enabled. Accounts an administrator re-enabled in the last 7 days are left alone.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "ZTNA21858"
        EXECUTIVETEXT
            Automatically disables external guest accounts that haven't been used for a number of days, reducing security risks from dormant accounts while maintaining access for active external collaborators. This helps maintain a clean user directory and reduces potential attack vectors.
        ADDEDCOMPONENT
            {"type":"number","name":"standards.DisableGuests.days","required":true,"defaultValue":90,"label":"Days of inactivity"}
            {"type":"switch","name":"standards.DisableGuests.IncludeNeverSignedIn","label":"Disable accounts that have not yet signed in","defaultValue":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2022-10-20
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        REQUIREDCAPABILITIES
            "AAD_PREMIUM"
            "AAD_PREMIUM_P2"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableGuests' -TenantFilter $Tenant -Preset Entra

    if ($TestResult -eq $false) {
        #writing to each item that the license is not present.
        foreach ($Template in $settings.TemplateList) {
            Set-CIPPStandardsCompareField -FieldName 'standards.DisableGuests' -FieldValue 'This tenant does not have the required license for this standard.' -Tenant $Tenant
        }
        return $true
    } #we're done.

    $checkDays = if ($Settings.days) { $Settings.days } else { 90 } # Default to 90 days if not set. Pre v8.5.0 compatibility
    # Off unless the template turns it on, so templates that predate the switch keep skipping guests with no sign-in on record.
    $IncludeNeverSignedIn = $Settings.IncludeNeverSignedIn -eq $true
    $Days = (Get-Date).AddDays(-$checkDays).ToUniversalTime()
    $Lookup = $Days.ToString('o')
    $AuditLookup = (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=createdDateTime le $Lookup and userType eq 'Guest' and accountEnabled eq true &`$select=id,UserPrincipalName,signInActivity,mail,userType,accountEnabled,createdDateTime,externalUserState" -scope 'https://graph.microsoft.com/.default' -tenantid $Tenant

        $StaleGuests = foreach ($guest in $GraphRequest) {
            # Newest of the interactive, non-interactive and successful sign-in timestamps - the view the
            # Entra portal and the inactive-guest alert give - rather than successful sign-ins alone, which
            # stay old while a blocked or disabled guest keeps trying.
            $LastSignIn = Get-CIPPLastSignInDateTime -SignInActivity $guest.signInActivity
            if ($LastSignIn) {
                if ($LastSignIn -le $Days) {
                    $guest | Add-Member -NotePropertyMembers ([ordered]@{
                            LastSignInDateTime = $LastSignIn
                            NeverSignedIn      = $false
                        }) -Force
                    $guest
                }
            } elseif ($IncludeNeverSignedIn) {
                # No sign-in attempt on record; createdDateTime is already <= $Days due to the server-side filter
                $guest | Add-Member -NotePropertyMembers ([ordered]@{
                        LastSignInDateTime = $null
                        NeverSignedIn      = $true
                    }) -Force
                $guest
            }
        }
        $GraphRequest = @($StaleGuests)
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableGuests state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $AuditResults = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Enable account' and activityDateTime ge $AuditLookup&`$select=targetResources" -scope 'https://graph.microsoft.com/.default' -tenantid $Tenant
    $RecentlyReactivatedUsers = @(foreach ($AuditEntry in $AuditResults) { $AuditEntry.targetResources[0].id }) | Select-Object -Unique

    $GraphRequest = @($GraphRequest | Where-Object { -not ($RecentlyReactivatedUsers -contains $_.id) })

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
                        $guest.accountEnabled = $false
                        $reason = if ($guest.NeverSignedIn) {
                            "never signed in, created $($guest.createdDateTime)"
                        } else {
                            "last sign-in: $($guest.LastSignInDateTime.ToString('o'))"
                        }
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabled guest $($guest.UserPrincipalName) ($($guest.id)). Reason: $reason" -sev Info
                    } else {
                        $errorMsg = if ($result.body.error.message) { $result.body.error.message } else { "Unknown error (Status: $($result.status))" }
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable guest $($guest.UserPrincipalName) ($($guest.id)): $errorMsg" -sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to process bulk disable guests request: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "No guest accounts without a sign-in in the last $checkDays days - all guest accounts are already compliant." -sev Info
        }
    }
    if ($Settings.alert -eq $true) {

        if ($GraphRequest.Count -gt 0) {
            $Filtered = @($GraphRequest | Select-Object -Property UserPrincipalName, id, signInActivity, LastSignInDateTime, NeverSignedIn, mail, userType, accountEnabled, externalUserState, createdDateTime)
            $NeverSignedInCount = @($Filtered | Where-Object { $_.NeverSignedIn }).Count
            $StaleCount = $Filtered.Count - $NeverSignedInCount
            $AlertMessage = "Stale guest accounts found: $($GraphRequest.Count) total ($StaleCount with no sign-in attempt in $checkDays days, $NeverSignedInCount never signed in and created more than $checkDays days ago)"
            Write-StandardsAlert -message $AlertMessage -object $Filtered -tenant $tenant -standardName 'DisableGuests' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message $AlertMessage -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "No stale guest accounts found (threshold: $checkDays days)." -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        $Filtered = @($GraphRequest | Where-Object { $_.accountEnabled } | Select-Object -Property UserPrincipalName, id, signInActivity, LastSignInDateTime, NeverSignedIn, mail, userType, accountEnabled, externalUserState, createdDateTime)
        $NeverSignedIn = @($Filtered | Where-Object { $_.NeverSignedIn })
        $StaleSignIns = @($Filtered | Where-Object { -not $_.NeverSignedIn })

        $CurrentValue = [PSCustomObject]@{
            GuestsDisabledAfterDays      = $checkDays
            GuestsIncludeNeverSignedIn   = $IncludeNeverSignedIn
            GuestsDisabledAccountCount   = $Filtered.Count
            GuestsStaleSignInCount       = $StaleSignIns.Count
            GuestsNeverSignedInCount     = $NeverSignedIn.Count
            GuestsDisabledAccountDetails = $Filtered
            GuestsNeverSignedInDetails   = $NeverSignedIn
        }

        $ExpectedValue = [PSCustomObject]@{
            GuestsDisabledAfterDays      = $checkDays
            GuestsIncludeNeverSignedIn   = $IncludeNeverSignedIn
            GuestsDisabledAccountCount   = 0
            GuestsStaleSignInCount       = 0
            GuestsNeverSignedInCount     = 0
            GuestsDisabledAccountDetails = @()
            GuestsNeverSignedInDetails   = @()
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableGuests' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableGuests' -FieldValue $Filtered -StoreAs json -Tenant $tenant
    }
}
