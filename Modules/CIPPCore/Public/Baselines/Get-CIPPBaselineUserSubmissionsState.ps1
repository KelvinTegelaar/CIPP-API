function Get-CIPPBaselineUserSubmissionsState {
    <#
    .SYNOPSIS
        Prepare hook for UserSubmissions: the report submission policy and rule posture.
    .DESCRIPTION
        Ports the classic's three-way matrix: enabled reporting to Microsoft, enabled
        reporting to a custom address (all three report types must carry exactly that
        address, with the rule enabled and routing to it), or disabled outright (no policy
        at all also counts as disabled). The graded shape is a flat set of booleans naming
        which leg is wrong, so the drift row says what to fix rather than 'not correct'.

        The email address runs through the tenant text replacement first, exactly as the
        classic replaced it - %variables% in the configured address resolve per tenant.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ReportSubmissionPolicy')
    $Rules = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ReportSubmissionRule')
    if ($Policies.Count -eq 0 -and $Rules.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ReportSubmissionPolicy')) {
        return @{ Current = $null }
    }
    $Policy = $Policies | Select-Object -First 1
    $Rule = $Rules | Select-Object -First 1

    $State = "$($Item.Variables.state.value ?? $Item.Variables.state)"
    if ($State -notin @('enable', 'disable')) { return @{ Current = $null } }
    $Email = "$($Item.Variables.email)"
    if (-not [string]::IsNullOrWhiteSpace($Email)) {
        $Email = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $Email
        if ($Email -notmatch '@') { return @{ Current = $null } }
    }

    # 'Send reported items to' only applies when an address is configured; blank or missing
    # keeps the original posture (Microsoft as well as the reporting mailbox).
    $Destination = "$($Item.Variables.reportDestination.value ?? $Item.Variables.reportDestination)"
    $ReportToMicrosoft = [string]::IsNullOrWhiteSpace($Email) -or $Destination -ne 'Mailbox'

    if ($State -eq 'enable' -and -not [string]::IsNullOrWhiteSpace($Email)) {
        $Expected = [PSCustomObject]@{ reportToMicrosoft = $ReportToMicrosoft; customAddressCorrect = $true; ruleCorrect = $true }
        $Current = [PSCustomObject]@{
            reportToMicrosoft    = [bool]$Policy.EnableReportToMicrosoft
            customAddressCorrect = [bool]($Policy.ReportJunkToCustomizedAddress -eq $true -and @($Policy.ReportJunkAddresses) -eq $Email -and
                $Policy.ReportNotJunkToCustomizedAddress -eq $true -and @($Policy.ReportNotJunkAddresses) -eq $Email -and
                $Policy.ReportPhishToCustomizedAddress -eq $true -and @($Policy.ReportPhishAddresses) -eq $Email)
            ruleCorrect          = [bool]($Rule -and "$($Rule.State)" -eq 'Enabled' -and @($Rule.SentTo) -eq $Email)
        }
    } elseif ($State -eq 'enable') {
        $Expected = [PSCustomObject]@{ reportToMicrosoft = $true; customAddressCorrect = $true; ruleCorrect = $true }
        $Current = [PSCustomObject]@{
            reportToMicrosoft    = [bool]$Policy.EnableReportToMicrosoft
            customAddressCorrect = [bool]($Policy.ReportJunkToCustomizedAddress -ne $true -and $Policy.ReportNotJunkToCustomizedAddress -ne $true -and
                $Policy.ReportPhishToCustomizedAddress -ne $true -and @($Policy.ReportJunkAddresses).Count -eq 0 -and
                @($Policy.ReportNotJunkAddresses).Count -eq 0 -and @($Policy.ReportPhishAddresses).Count -eq 0)
            ruleCorrect          = [bool](-not $Rule -or "$($Rule.State)" -ne 'Enabled')
        }
    } else {
        $Expected = [PSCustomObject]@{ reportingDisabled = $true; ruleCorrect = $true }
        $Current = [PSCustomObject]@{
            reportingDisabled = [bool](-not $Policy -or ($Policy.EnableReportToMicrosoft -ne $true -and
                    $Policy.ReportJunkToCustomizedAddress -ne $true -and $Policy.ReportNotJunkToCustomizedAddress -ne $true -and
                    $Policy.ReportPhishToCustomizedAddress -ne $true))
            ruleCorrect       = [bool](-not $Rule -or "$($Rule.State)" -ne 'Enabled')
        }
    }

    # Carried for the executor: which objects exist decides New- vs Set- vs Remove-.
    $Current | Add-Member -NotePropertyName 'policyExists' -NotePropertyValue ([bool]$Policy)
    $Current | Add-Member -NotePropertyName 'ruleExists' -NotePropertyValue ([bool]$Rule)
    $Current | Add-Member -NotePropertyName 'ruleEnabled' -NotePropertyValue ([bool]($Rule -and "$($Rule.State)" -eq 'Enabled'))
    $Current | Add-Member -NotePropertyName 'resolvedEmail' -NotePropertyValue $Email
    $Current | Add-Member -NotePropertyName 'reportDestination' -NotePropertyValue $Destination

    @{ Expected = $Expected; Current = $Current }
}
