function Invoke-CIPPBaselineGlobalQuarantineSettings {
    <#
    .SYNOPSIS
        GlobalQuarantineSettings executor: writes the global quarantine notification
        branding.
    .DESCRIPTION
        Exchange requires ALL THREE per-language arrays on every write, with counts equal
        to the language count - so a configured text fans across every tenant language, and
        an UNCONFIGURED field resends the tenant's current values (padded with the first
        value when the language list grew). Omitting an array fails the whole write with
        'counts must be equal'; nulling it - the classic's behaviour for unset fields -
        would clear real branding.

        The Microsoft default policy (DefaultGlobalPolicy) cannot be modified, so meeting
        it means CREATING the custom DefaultGlobalTag; anything else is Set- in place.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Languages = @($Current.languages)
    if ($Languages.Count -eq 0) { $Languages = @('Default') }

    $BuildArray = {
        param($Configured, $Existing)
        if (-not [string]::IsNullOrWhiteSpace("$Configured")) { return @($Languages | ForEach-Object { "$Configured" }) }
        $Values = @($Existing)
        if ($Values.Count -eq $Languages.Count) { return $Values }
        # Language list changed since the values were written - pad with the first value
        # (or blanks) so the counts Exchange insists on line up.
        $Fill = if ($Values.Count -gt 0) { "$($Values[0])" } else { '' }
        return @(1..$Languages.Count | ForEach-Object { $Fill })
    }
    $Params = @{
        MultiLanguageSetting          = $Languages
        MultiLanguageSenderName       = & $BuildArray $Remediate.senderName $Current.currentSenderNames
        ESNCustomSubject              = & $BuildArray $Remediate.customSubject $Current.currentSubjects
        MultiLanguageCustomDisclaimer = & $BuildArray $Remediate.customDisclaimer $Current.currentDisclaimers
    }
    if (-not [string]::IsNullOrWhiteSpace("$($Remediate.fromAddress)")) { $Params['EndUserSpamNotificationCustomFromAddress'] = "$($Remediate.fromAddress)" }
    $Params['OrganizationBrandingEnabled'] = [bool]($Remediate.organizationBrandingEnabled -eq $true)

    if ("$($Current.policyName)" -eq 'DefaultGlobalPolicy') {
        $Params['Name'] = 'DefaultGlobalTag'
        $Params['QuarantinePolicyType'] = 'GlobalQuarantinePolicy'
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-QuarantinePolicy' -cmdParams $Params
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Created the custom global quarantine policy with the configured branding.' -Sev 'Info'
    } else {
        $Params['Identity'] = "$($Current.policyIdentity)"
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-QuarantinePolicy' -cmdParams $Params
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Updated the global quarantine policy branding.' -Sev 'Info'
    }
}
