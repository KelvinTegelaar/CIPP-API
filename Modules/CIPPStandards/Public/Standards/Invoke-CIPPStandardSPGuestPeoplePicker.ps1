function Invoke-CIPPStandardSPGuestPeoplePicker {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPGuestPeoplePicker
    .SYNOPSIS
        (Label) Show guest users in the SharePoint People Picker
    .DESCRIPTION
        (Helptext) Controls whether guest (external) users already in the tenant appear as suggestions in the SharePoint and OneDrive People Picker. Enforces the wanted state on BOTH the tenant default and every existing site collection - they are set independently, so changing the tenant default does not update existing sites. State is read from the SharePoint reporting cache; remediation writes the tenant default and each drifted site.
        (DocsDescription) Enforces ShowPeoplePickerSuggestionsForGuestUsers at both levels it is set independently: the tenant default (Set-SPOTenant) and each site collection (Set-SPOSite). Guests are not shown by default even when they exist in the tenant, and changing the tenant default does not retroactively change existing sites, so both are covered. Current state comes from the SPOSites reporting cache, so drift detection makes no live calls.
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

    # State from the reporting cache (tenant + site rows). No live reads for evaluation.
    $Rows = @(New-CIPPDbRequest -TenantFilter $Tenant -Type 'SPOSites' | Where-Object { $_ })
    if ($Rows.Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SPGuestPeoplePicker: no cached SharePoint data yet - it will populate on the next SharePoint report cache run' -sev Info
        return
    }
    $TenantRow = $Rows | Where-Object { $_.Scope -eq 'tenant' } | Select-Object -First 1
    $SiteRows = @($Rows | Where-Object { $_.Scope -eq 'site' -and $_.Url })

    $TenantIsCorrect = $TenantRow -and ([bool]$TenantRow.ShowPeoplePickerSuggestionsForGuestUsers -eq $WantedState)
    $NonCompliantSites = @($SiteRows | Where-Object { [bool]$_.ShowPeoplePickerSuggestionsForGuestUsers -ne $WantedState })
    $StateIsCorrect = $TenantIsCorrect -and ($NonCompliantSites.Count -eq 0)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Guest People Picker suggestions are already correctly set to $HumanReadableState on the tenant default and all $($SiteRows.Count) sites" -sev Info
        } else {
            if (-not $TenantIsCorrect) {
                try {
                    # Remediation writes live; a fresh tenant identity is required for the CSOM write.
                    $null = Get-CIPPSPOTenant -TenantFilter $Tenant -UseCertificate | Set-CIPPSPOTenant -Properties @{ ShowPeoplePickerSuggestionsForGuestUsers = $WantedState } -UseCertificate
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set the tenant default guest People Picker suggestions to $HumanReadableState" -sev Info
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set the tenant default guest People Picker suggestions to $HumanReadableState. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                }
            }
            $Failed = 0
            foreach ($Site in $NonCompliantSites) {
                try {
                    $null = Set-CIPPSPOSite -TenantFilter $Tenant -SiteUrl $Site.Url -Properties @{ ShowPeoplePickerSuggestionsForGuestUsers = $WantedState } -UseCertificate
                } catch {
                    $Failed++
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set guest People Picker suggestions to $HumanReadableState on $($Site.Url): $($_.Exception.Message)" -sev Error
                }
            }
            if ($NonCompliantSites.Count -gt 0) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set guest People Picker suggestions to $HumanReadableState on $($NonCompliantSites.Count - $Failed) of $($NonCompliantSites.Count) drifted sites" -sev Info
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Guest People Picker suggestions are correctly set to $HumanReadableState everywhere" -sev Info
        } else {
            $TenantPart = if ($TenantIsCorrect) { 'the tenant default is correct' } else { "the tenant default is not $HumanReadableState" }
            $Message = "Guest People Picker suggestions are not set to ${HumanReadableState}: $TenantPart and $($NonCompliantSites.Count) site(s) differ"
            Write-StandardsAlert -message $Message -object @{ TenantDefault = $TenantRow.ShowPeoplePickerSuggestionsForGuestUsers; NonCompliantSiteCount = $NonCompliantSites.Count } -tenant $Tenant -standardName 'SPGuestPeoplePicker' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $Message -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            TenantDefault         = $TenantRow.ShowPeoplePickerSuggestionsForGuestUsers
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
