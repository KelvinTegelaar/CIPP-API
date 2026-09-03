function Invoke-CIPPStandardSPGuestPeoplePicker {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPGuestPeoplePicker
    .SYNOPSIS
        (Label) Show guest users in the SharePoint People Picker
    .DESCRIPTION
        (Helptext) Controls whether guest (external) users already in the tenant appear as suggestions in the SharePoint and OneDrive People Picker. Enforces the wanted state on BOTH the tenant default and every existing site collection - they are set independently, so changing the tenant default does not update existing sites. Reads live SharePoint state before deciding what to change, and re-reads each changed site afterwards to report the true result.
        (DocsDescription) Enforces ShowPeoplePickerSuggestionsForGuestUsers at both levels it is set independently: the tenant default (Set-SPOTenant) and each site collection (Set-SPOSite). Guests are not shown by default even when they exist in the tenant, and changing the tenant default does not retroactively change existing sites, so both are covered. Current state is read live from SharePoint before remediation; after remediation each changed site is re-read authoritatively (single-site, not the eventually-consistent enumeration) so the reported status reflects the actual result.
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

    # Read LIVE state before deciding anything: the tenant default (authoritative single read) and
    # every site (bulk enumeration - fresher than the nightly cache). SharePoint app-only needs cert.
    try {
        $CurrentTenant = Get-CIPPSPOTenant -TenantFilter $Tenant -UseCertificate |
            Select-Object _ObjectIdentity_, TenantFilter, ShowPeoplePickerSuggestionsForGuestUsers
        $Sites = @(Get-CIPPSPOSite -TenantFilter $Tenant -UseCertificate | Where-Object { $_ -and $_.Url })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SPGuestPeoplePicker state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    $TenantValue = [bool]$CurrentTenant.ShowPeoplePickerSuggestionsForGuestUsers
    $NonCompliantSites = @($Sites | Where-Object { [bool]$_.ShowPeoplePickerSuggestionsForGuestUsers -ne $WantedState })
    $TenantIsCorrect = ($TenantValue -eq $WantedState)
    $StateIsCorrect = $TenantIsCorrect -and ($NonCompliantSites.Count -eq 0)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Guest People Picker suggestions are already correctly set to $HumanReadableState on the tenant default and all $($Sites.Count) sites" -sev Info
        } else {
            if (-not $TenantIsCorrect) {
                try {
                    $CurrentTenant | Set-CIPPSPOTenant -Properties @{ ShowPeoplePickerSuggestionsForGuestUsers = $WantedState } -UseCertificate
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set the tenant default guest People Picker suggestions to $HumanReadableState. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                }
            }
            if ($NonCompliantSites.Count -gt 0) {
                $BulkSites = @($NonCompliantSites | ForEach-Object { @{ SiteUrl = $_.Url; Properties = @{ ShowPeoplePickerSuggestionsForGuestUsers = $WantedState } } })
                $null = Set-CIPPSPOSiteBulk -TenantFilter $Tenant -Sites $BulkSites -UseCertificate
            }

            # Verify AFTER the writes by re-reading authoritatively (single-site, never the lagging
            # enumeration): the tenant default and only the sites we changed. Report the true result.
            $TenantValue = [bool](Get-CIPPSPOTenant -TenantFilter $Tenant -UseCertificate).ShowPeoplePickerSuggestionsForGuestUsers
            $TenantIsCorrect = ($TenantValue -eq $WantedState)

            if ($NonCompliantSites.Count -gt 0) {
                $Verified = @(Get-CIPPSPOSiteBulk -TenantFilter $Tenant -SiteUrls @($NonCompliantSites.Url) -UseCertificate)
                $StillNonCompliant = @($Verified | Where-Object { -not $_.Success -or [bool]$_.Site.ShowPeoplePickerSuggestionsForGuestUsers -ne $WantedState })
                foreach ($Bad in $StillNonCompliant) {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Guest People Picker still not $HumanReadableState on $($Bad.SiteUrl)$(if ($Bad.Error) { ": $($Bad.Error)" })" -sev Error
                }
                $Fixed = $NonCompliantSites.Count - $StillNonCompliant.Count
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Verified guest People Picker set to $HumanReadableState on $Fixed of $($NonCompliantSites.Count) sites (re-read after remediation)" -sev Info
                $NonCompliantSites = $StillNonCompliant
            }
            $StateIsCorrect = $TenantIsCorrect -and ($NonCompliantSites.Count -eq 0)
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
