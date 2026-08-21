function Invoke-CIPPBaselineReusableSettingsTemplate {
    <#
    .SYNOPSIS
        ReusableSettingsTemplate executor: creates or overwrites the reusable setting.
    .DESCRIPTION
        PUT over the existing object when the hook found one, POST otherwise - the classic's
        exact write. The body is the template's raw Graph JSON, untouched: a reusable
        setting is a settingInstance tree that only round-trips whole.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    if ([string]::IsNullOrWhiteSpace("$($Current.rawJSON)")) { return }

    if ($Current.existingId) {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings/$($Current.existingId)" -tenantid $TenantFilter -type PUT -body $Current.rawJSON
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Updated reusable setting from template.' -Sev 'Info'
    } else {
        $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings' -tenantid $TenantFilter -type POST -body $Current.rawJSON
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Created reusable setting from template.' -Sev 'Info'
    }
}
