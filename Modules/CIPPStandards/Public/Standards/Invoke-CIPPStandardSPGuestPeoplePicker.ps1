function Invoke-CIPPStandardSPGuestPeoplePicker {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPGuestPeoplePicker
    .SYNOPSIS
        (Label) Show guest users in the SharePoint People Picker
    .DESCRIPTION
        (Helptext) Controls whether guest (external) users already in the tenant appear as suggestions in the SharePoint and OneDrive People Picker. Enforces the wanted state on BOTH the tenant default and every existing site collection - they are set independently, so changing the tenant default does not update existing sites. The per-site picture is read from the SharePoint reporting cache (refreshed daily), so a large tenant is never enumerated live during a run; a 24h rerun guard stops the write sweep from repeating before that cache refreshes and re-evaluates the result.
        (DocsDescription) Enforces ShowPeoplePickerSuggestionsForGuestUsers at both levels it is set independently: the tenant default (Set-SPOTenant) and each site collection (Set-SPOSite). Which sites differ is decided from the SPOSites reporting cache (populated by the daily SharePoint cache run) rather than the live site enumeration, which on a large tenant is hundreds of CSOM calls and lags a just-applied write. The tenant default is read through the cached SharePoint tenant configuration. Remediation sets the tenant default and sweeps every differing site once, then records a 24-hour rerun guard: the write is not repeated until the next daily cache run reflects the change, at which point the standard re-evaluates from the refreshed cache. Guests are not shown by default even when they exist in the tenant, and changing the tenant default does not retroactively change existing sites, so both are covered.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        EXECUTIVETEXT
            Makes existing external collaborators discoverable (or hidden) when sharing SharePoint and OneDrive content, consistently across the tenant default and every existing site. This keeps the sharing experience predictable and prevents individual sites from drifting away from the agreed collaboration posture.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Guest People Picker suggestions","name":"standards.SPGuestPeoplePicker.state","options":[{"label":"Show guests in the People Picker","value":"true"},{"label":"Hide guests in the People Picker","value":"false"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-09-03
        POWERSHELLEQUIVALENT
            Set-SPOTenant / Set-SPOSite -ShowPeoplePickerSuggestionsForGuestUsers \$true or \$false
        RECOMMENDEDBY
            "CIPP"
        REQUIREDCAPABILITIES
            "SHAREPOINTWAC"
            "SHAREPOINTSTANDARD"
            "SHAREPOINTENTERPRISE"
            "SHAREPOINTENTERPRISE_EDU"
            "ONEDRIVE_BASIC"
            "ONEDRIVE_ENTERPRISE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SPGuestPeoplePicker' -TenantFilter $Tenant -Preset SharePoint

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    # Input validation
    $StateValue = $Settings.state.value ?? $Settings.state
    if (([string]::IsNullOrWhiteSpace($StateValue) -or $StateValue -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SPGuestPeoplePicker: Invalid state parameter set' -sev Error
        return
    }
    $WantedState = [System.Convert]::ToBoolean($StateValue)
    $HumanReadableState = if ($WantedState -eq $true) { 'shown' } else { 'hidden' }

    # Decide what to change from cache, not live. The per-site picture comes from the SPOSites
    # reporting cache (refreshed by the daily SharePoint CIPPDB run) - never the live enumeration,
    # which on a large tenant is hundreds of CSOM calls and lags a just-applied write by minutes.
    # The tenant default is a single setting read through Get-CIPPSPOTenant's own 1h cache - unlike
    # the delegated SPOTenant reporting collector, this works app-only with the certificate on
    # tenants without a SharePoint-admin GDAP user - and the same object is the write handle below.
    try {
        $CurrentTenant = Get-CIPPSPOTenant -TenantFilter $Tenant -UseCertificate | Select-Object -First 1
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not read the SharePoint tenant configuration for SPGuestPeoplePicker on $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }
    if (-not $CurrentTenant) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SPGuestPeoplePicker: no SharePoint tenant configuration available yet - it will populate on the next SharePoint cache run' -sev Info
        return
    }

    $Sites = @(New-CIPPDbRequest -TenantFilter $Tenant -Type 'SPOSites' | Where-Object { $_ -and $_.Url })
    $TenantValue = [bool]$CurrentTenant.ShowPeoplePickerSuggestionsForGuestUsers
    $NonCompliantSites = @($Sites | Where-Object { [bool]$_.ShowPeoplePickerSuggestionsForGuestUsers -ne $WantedState })
    $TenantIsCorrect = ($TenantValue -eq $WantedState)
    $StateIsCorrect = $TenantIsCorrect -and ($NonCompliantSites.Count -eq 0)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Guest People Picker suggestions are already correctly set to $HumanReadableState on the tenant default and all $($Sites.Count) sites" -sev Info
        } elseif (Test-CIPPRerun -Tenant $Tenant -API 'SPGuestPeoplePicker' -Interval 86400) {
            # The write sweep already ran for this tenant within the last 24h (Test-CIPPRerun records
            # it, and the baseline executor shares this key). Its input, the SPOSites cache, only
            # refreshes daily, so re-running now would re-issue the same writes against a stale picture
            # and push SharePoint into throttling. Wait for the next daily cache run to reflect the
            # change and re-evaluate the true result. Alert/report below still run every time.
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SPGuestPeoplePicker: write sweep already ran within the last 24h - skipping it until the next cache run re-evaluates the result' -sev Info
        } else {
            if (-not $TenantIsCorrect) {
                try {
                    $null = $CurrentTenant | Set-CIPPSPOTenant -Properties @{ ShowPeoplePickerSuggestionsForGuestUsers = $WantedState } -UseCertificate
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set the tenant default guest People Picker suggestions to $HumanReadableState. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                }
            }
            if ($NonCompliantSites.Count -gt 0) {
                $BulkSites = @($NonCompliantSites | ForEach-Object { @{ SiteUrl = $_.Url; Properties = @{ ShowPeoplePickerSuggestionsForGuestUsers = $WantedState } } })
                $Results = @(Set-CIPPSPOSiteBulk -TenantFilter $Tenant -Sites $BulkSites -UseCertificate)
                $FailedSites = @($Results | Where-Object { -not $_.Success })
                foreach ($Bad in $FailedSites) {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set guest People Picker to $HumanReadableState on $($Bad.SiteUrl)$(if ($Bad.Error) { ": $($Bad.Error)" })" -sev Error
                }
                $Succeeded = $Results.Count - $FailedSites.Count
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set guest People Picker to $HumanReadableState on $Succeeded of $($NonCompliantSites.Count) site(s)" -sev Info
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Guest People Picker suggestions are correctly set to $HumanReadableState everywhere" -sev Info
        } else {
            $TenantPart = if ($TenantIsCorrect) { 'the tenant default is correct' } else { "the tenant default is not $HumanReadableState" }
            $Message = "Guest People Picker suggestions are not set to ${HumanReadableState}: $TenantPart and $($NonCompliantSites.Count) site(s) differ"
            Write-StandardsAlert -message $Message -object @{ TenantDefault = $TenantValue; NonCompliantSiteCount = $NonCompliantSites.Count } -tenant $Tenant -standardName 'SPGuestPeoplePicker' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $Message -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            TenantDefault         = $TenantValue
            NonCompliantSiteCount = $NonCompliantSites.Count
        }
        $ExpectedValue = @{
            TenantDefault         = $WantedState
            NonCompliantSiteCount = 0
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SPGuestPeoplePicker' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'SPGuestPeoplePicker' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
