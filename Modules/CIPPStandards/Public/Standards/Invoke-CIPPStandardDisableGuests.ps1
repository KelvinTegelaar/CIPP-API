function Invoke-CIPPStandardDisableGuests {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableGuests
    .SYNOPSIS
        (Label) Disable Guest accounts that have not logged on for a number of days
    .DESCRIPTION
        (Helptext) Blocks login for guest users whose most recent sign-in attempt, interactive or non-interactive, is older than the number of days. Optionally soft-deletes already-disabled guests after a configurable grace period past that threshold (0 = never delete). Guests that have never signed in are only included when 'Disable accounts that have not yet signed in' is enabled. Accounts an administrator re-enabled in the last 7 days are left alone. Deleted guests remain recoverable from Deleted Items for about 30 days.
        (DocsDescription) Blocks login for guest users whose most recent sign-in attempt, interactive or non-interactive, is older than the number of days. Remediation first disables stale enabled guests, and later soft-deletes guests that are already disabled once they have been inactive for the disable threshold plus the configured grace delta (deletion age = days + deleteGraceDays). The disable-before-delete grace is further guaranteed by never deleting a guest in the same pass it was disabled. Guests that have never signed in are only included when 'Disable accounts that have not yet signed in' is enabled. Accounts an administrator re-enabled in the last 7 days are left alone. Graph user DELETE is a soft-delete (recoverable from Deleted Items for about 30 days), which lets a later re-invite create a clean guest object instead of colliding with a disabled account.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "ZTNA21858"
        EXECUTIVETEXT
            Automatically disables external guest accounts that haven't been used for a number of days, and can optionally remove already-disabled dormant guests after an additional grace period. This reduces security risks from abandoned external access, keeps the directory clean, and avoids errors when previously disabled guests need to be invited back.
        ADDEDCOMPONENT
            {"type":"number","name":"standards.DisableGuests.days","required":true,"defaultValue":90,"label":"Days of inactivity"}
            {"type":"number","name":"standards.DisableGuests.deleteGraceDays","label":"Grace days after disable before deletion (0 = never delete). Guests are deleted once inactive for the disable threshold plus this many additional days.","defaultValue":0,"validators":{"min":{"value":0,"message":"Minimum value is 0"}}}
            {"type":"switch","name":"standards.DisableGuests.IncludeNeverSignedIn","label":"Disable accounts that have not yet signed in","defaultValue":false}
        IMPACT
            High Impact
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

    $checkDays = if ($Settings.days) { [int]$Settings.days } else { 90 } # Default to 90 days if not set. Pre v8.5.0 compatibility
    # Off unless the template turns it on, so templates that predate the switch keep skipping guests with no sign-in on record.
    $IncludeNeverSignedIn = $Settings.IncludeNeverSignedIn -eq $true
    # deleteGraceDays is a delta on top of days; missing/blank/0 preserves disable-only behaviour for existing templates.
    $DeleteDelta = if ([string]::IsNullOrWhiteSpace([string]$Settings.deleteGraceDays)) { 0 } else { [int]$Settings.deleteGraceDays }
    if ($DeleteDelta -lt 0) { $DeleteDelta = 0 }
    $DeleteEnabled = $DeleteDelta -gt 0
    $DeleteAge = $checkDays + $DeleteDelta

    $Days = (Get-Date).AddDays(-$checkDays).ToUniversalTime()
    $Lookup = $Days.ToString('o')
    $DeleteDate = (Get-Date).AddDays(-$DeleteAge).ToUniversalTime()
    $DeleteLookup = $DeleteDate.ToString('o')
    $GuestSelect = 'id,UserPrincipalName,signInActivity,mail,userType,accountEnabled,createdDateTime,externalUserState'

    # Annotates a guest with LastSignInDateTime / NeverSignedIn and returns $true when it is stale
    # relative to $Cutoff. Newest of interactive, non-interactive and successful sign-in timestamps -
    # the view the Entra portal and the inactive-guest alert give - rather than successful sign-ins
    # alone, which stay old while a blocked or disabled guest keeps trying.
    $TestStale = {
        param($Guest, $Cutoff, [bool]$IncludeNeverSignedIn)
        $LastSignIn = Get-CIPPLastSignInDateTime -SignInActivity $Guest.signInActivity
        if ($LastSignIn) {
            if ($LastSignIn -le $Cutoff) {
                $Guest | Add-Member -NotePropertyMembers ([ordered]@{
                        LastSignInDateTime = $LastSignIn
                        NeverSignedIn      = $false
                    }) -Force
                return $true
            }
            return $false
        }
        if ($IncludeNeverSignedIn) {
            # No sign-in attempt on record; createdDateTime is already <= cutoff due to the server-side filter
            $Guest | Add-Member -NotePropertyMembers ([ordered]@{
                    LastSignInDateTime = $null
                    NeverSignedIn      = $true
                }) -Force
            return $true
        }
        return $false
    }

    try {
        $EnabledGuests = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=createdDateTime le $Lookup and userType eq 'Guest' and accountEnabled eq true&`$select=$GuestSelect" -scope 'https://graph.microsoft.com/.default' -tenantid $Tenant)
        $GuestsToDisable = @(foreach ($guest in $EnabledGuests) {
                if (& $TestStale $guest $Days $IncludeNeverSignedIn) {
                    $guest
                }
            })

        $GuestsToDelete = @()
        $GuestsMeetingDeleteThreshold = @()
        if ($DeleteEnabled) {
            $DisabledGuests = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=createdDateTime le $DeleteLookup and userType eq 'Guest' and accountEnabled eq false&`$select=$GuestSelect" -scope 'https://graph.microsoft.com/.default' -tenantid $Tenant)
            $GuestsMeetingDeleteThreshold = @(foreach ($guest in $DisabledGuests) {
                    if (& $TestStale $guest $DeleteDate $IncludeNeverSignedIn) {
                        $guest
                    }
                })
            # Only already-disabled guests are deleted this run; guests disabled in this same pass are left for a later run.
            $GuestsToDelete = @($GuestsMeetingDeleteThreshold)
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableGuests state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Same as baseline: audit only matters for the disable set. Skip it when empty so delete-only
    # runs are not blocked by an audit failure, and swallow audit errors so a lookup outage cannot
    # abort remediation (fail open on the 7-day re-enable skip).
    if ($GuestsToDisable.Count -gt 0) {
        $AuditLookup = (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
        $RecentlyReactivatedUsers = @(try {
                $AuditResults = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Enable account' and activityDateTime ge $AuditLookup&`$select=targetResources" -scope 'https://graph.microsoft.com/.default' -tenantid $Tenant
                @(foreach ($AuditEntry in $AuditResults) { $AuditEntry.targetResources[0].id }) | Select-Object -Unique
            } catch {
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "DisableGuests: reactivation audit lookup failed: $($_.Exception.Message)" -Sev Warning
                @()
            })
        $GuestsToDisable = @($GuestsToDisable | Where-Object { $RecentlyReactivatedUsers -notcontains $_.id })
    }

    if ($Settings.remediate -eq $true) {
        $DisabledCount = 0
        $DeletedCount = 0
        $FailedCount = 0
        $DeletedGuestIds = [System.Collections.Generic.List[string]]::new()

        if ($GuestsToDisable.Count -gt 0) {
            $int = 0
            $BulkRequests = foreach ($guest in $GuestsToDisable) {
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
                    $guest = $GuestsToDisable[$i]

                    if ($result.status -eq 200 -or $result.status -eq 204) {
                        $DisabledCount++
                        $guest.accountEnabled = $false
                        $reason = if ($guest.NeverSignedIn) {
                            "never signed in, created $($guest.createdDateTime)"
                        } else {
                            "last sign-in: $($guest.LastSignInDateTime.ToString('o'))"
                        }
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabled guest $($guest.UserPrincipalName) ($($guest.id)). Reason: $reason" -sev Info
                    } else {
                        $FailedCount++
                        $errorMsg = if ($result.body.error.message) { $result.body.error.message } else { "Unknown error (Status: $($result.status))" }
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable guest $($guest.UserPrincipalName) ($($guest.id)): $errorMsg" -sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $FailedCount += $GuestsToDisable.Count
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to process bulk disable guests request: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }

        if ($GuestsToDelete.Count -gt 0) {
            $int = 0
            $DeleteMap = @{}
            $DeleteRequests = foreach ($guest in $GuestsToDelete) {
                $CurrentId = $int++
                $DeleteMap[$CurrentId] = $guest
                @{
                    id     = $CurrentId
                    method = 'DELETE'
                    url    = "users/$($guest.id)"
                }
            }

            try {
                $DeleteResults = New-GraphBulkRequest -tenantid $tenant -Requests @($DeleteRequests)
                foreach ($result in $DeleteResults) {
                    $guest = $DeleteMap[[int]$result.id]
                    if ($null -eq $guest) { continue }

                    if ($result.status -eq 200 -or $result.status -eq 204) {
                        $DeletedCount++
                        $null = $DeletedGuestIds.Add([string]$guest.id)
                        $reason = if ($guest.NeverSignedIn) {
                            "never signed in, created $($guest.createdDateTime)"
                        } else {
                            "last sign-in: $($guest.LastSignInDateTime.ToString('o'))"
                        }
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Deleted guest $($guest.UserPrincipalName) ($($guest.id)). Reason: $reason" -sev Info
                    } else {
                        $FailedCount++
                        $errorMsg = if ($result.body.error.message) { $result.body.error.message } else { "Unknown error (Status: $($result.status))" }
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to delete guest $($guest.UserPrincipalName) ($($guest.id)): $errorMsg" -sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $FailedCount += $GuestsToDelete.Count
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to process bulk delete guests request: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }

        if ($DeletedGuestIds.Count -gt 0) {
            $GuestsToDelete = @($GuestsToDelete | Where-Object { $_.id -notin $DeletedGuestIds })
            $GuestsMeetingDeleteThreshold = @($GuestsMeetingDeleteThreshold | Where-Object { $_.id -notin $DeletedGuestIds })
        }

        if ($DisabledCount -gt 0 -or $DeletedCount -gt 0 -or $FailedCount -gt 0) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "DisableGuests remediation completed. Disabled: $DisabledCount. Deleted: $DeletedCount. Failed: $FailedCount." -sev Info
        } elseif ($GuestsToDisable.Count -eq 0 -and $GuestsToDelete.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "No guest accounts without a sign-in in the last $checkDays days - all guest accounts are already compliant." -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        $AlertGuests = @($GuestsToDisable)
        if ($DeleteEnabled) {
            $AlertGuests = @($GuestsToDisable + $GuestsMeetingDeleteThreshold)
        }

        if ($AlertGuests.Count -gt 0) {
            $Filtered = @($AlertGuests | Select-Object -Property UserPrincipalName, id, signInActivity, LastSignInDateTime, NeverSignedIn, mail, userType, accountEnabled, externalUserState, createdDateTime)
            $NeverSignedInCount = @($GuestsToDisable | Where-Object { $_.NeverSignedIn }).Count
            $StaleCount = $GuestsToDisable.Count - $NeverSignedInCount
            $AlertMessage = "Stale guest accounts found: $($GuestsToDisable.Count) total ($StaleCount with no sign-in attempt in $checkDays days, $NeverSignedInCount never signed in and created more than $checkDays days ago)"
            if ($DeleteEnabled) {
                $AlertMessage += ", $($GuestsMeetingDeleteThreshold.Count) meeting delete threshold (inactive $DeleteAge days, already disabled)"
            }
            Write-StandardsAlert -message $AlertMessage -object $Filtered -tenant $tenant -standardName 'DisableGuests' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message $AlertMessage -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "No stale guest accounts found (threshold: $checkDays days)." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        # After a remediate pass, successfully disabled guests have accountEnabled flipped off so
        # the compare field reflects remaining work - same as the pre-delete-grace behaviour.
        $Filtered = @($GuestsToDisable | Where-Object { $_.accountEnabled } | Select-Object -Property UserPrincipalName, id, signInActivity, LastSignInDateTime, NeverSignedIn, mail, userType, accountEnabled, externalUserState, createdDateTime)
        $NeverSignedIn = @($Filtered | Where-Object { $_.NeverSignedIn })
        $StaleSignIns = @($Filtered | Where-Object { -not $_.NeverSignedIn })
        $DeleteDetails = if ($DeleteEnabled) {
            @($GuestsMeetingDeleteThreshold | Select-Object -Property UserPrincipalName, id, signInActivity, LastSignInDateTime, NeverSignedIn, mail, userType, accountEnabled, externalUserState, createdDateTime)
        } else {
            @()
        }

        $CurrentValue = [PSCustomObject]@{
            GuestsDisabledAfterDays      = $checkDays
            GuestsDeleteGraceDays        = $DeleteDelta
            GuestsIncludeNeverSignedIn   = $IncludeNeverSignedIn
            GuestsDisabledAccountCount   = $Filtered.Count
            GuestsStaleSignInCount       = $StaleSignIns.Count
            GuestsNeverSignedInCount     = $NeverSignedIn.Count
            GuestsDisabledAccountDetails = $Filtered
            GuestsNeverSignedInDetails   = $NeverSignedIn
            GuestsMeetingDeleteThreshold = if ($DeleteEnabled) { $DeleteDetails } else { 'Deletion disabled' }
            GuestsMeetingDeleteCount     = if ($DeleteEnabled) { $DeleteDetails.Count } else { 0 }
        }

        $ExpectedValue = [PSCustomObject]@{
            GuestsDisabledAfterDays      = $checkDays
            GuestsDeleteGraceDays        = $DeleteDelta
            GuestsIncludeNeverSignedIn   = $IncludeNeverSignedIn
            GuestsDisabledAccountCount   = 0
            GuestsStaleSignInCount       = 0
            GuestsNeverSignedInCount     = 0
            GuestsDisabledAccountDetails = @()
            GuestsNeverSignedInDetails   = @()
            GuestsMeetingDeleteThreshold = if ($DeleteEnabled) { @() } else { 'Deletion disabled' }
            GuestsMeetingDeleteCount     = 0
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableGuests' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableGuests' -FieldValue $Filtered -StoreAs json -Tenant $tenant
    }
}
