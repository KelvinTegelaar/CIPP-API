function Invoke-CIPPBaselineGlobalQuarantineSettings {
    <#
    .SYNOPSIS
        GlobalQuarantineSettings executor: writes the global quarantine notification
        branding.
    .DESCRIPTION
        The per-language texts fan out across exactly the languages the tenant has
        configured - one copy per language, the classic's write. The Microsoft default
        policy (DefaultGlobalPolicy) cannot be modified, so meeting it means CREATING the
        custom DefaultGlobalTag; anything else is Set- in place. Only configured fields are
        written, mirroring the compare.
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

    $Params = @{ MultiLanguageSetting = $Languages }
    if (-not [string]::IsNullOrWhiteSpace("$($Remediate.senderName)")) { $Params['MultiLanguageSenderName'] = @($Languages | ForEach-Object { "$($Remediate.senderName)" }) }
    if (-not [string]::IsNullOrWhiteSpace("$($Remediate.customSubject)")) { $Params['ESNCustomSubject'] = @($Languages | ForEach-Object { "$($Remediate.customSubject)" }) }
    if (-not [string]::IsNullOrWhiteSpace("$($Remediate.customDisclaimer)")) { $Params['MultiLanguageCustomDisclaimer'] = @($Languages | ForEach-Object { "$($Remediate.customDisclaimer)" }) }
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
