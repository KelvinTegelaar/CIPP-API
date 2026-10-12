function Invoke-CIPPBaselineCopilotLimitedMode {
    <#
    .SYNOPSIS
        CopilotLimitedMode executor: sets Copilot limited mode and its scoping group.
    .DESCRIPTION
        One PATCH with the odata-typed body, DELEGATED - the Copilot admin settings API
        rejects app-only tokens, which is why the classic (and the cache collector) stay on
        the delegated token. Disabling clears the group id, matching the classic.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Enabled = [bool]($Remediate.limitedModeEnabled -eq $true -or "$($Remediate.limitedModeEnabled)" -eq 'True')
    if ($Enabled -and [string]::IsNullOrWhiteSpace("$($Current.resolvedGroupId)")) {
        throw 'Copilot limited mode: no resolved scoping group - refusing to enable without one.'
    }

    $Body = [ordered]@{
        '@odata.type'     = '#microsoft.graph.copilotAdminLimitedMode'
        isEnabledForGroup = $Enabled
        groupId           = if ($Enabled) { "$($Current.resolvedGroupId)" } else { $null }
    } | ConvertTo-Json -Compress
    $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/copilot/admin/settings/limitedMode' -type PATCH -body $Body -ContentType 'application/json'
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Set Copilot limited mode to $Enabled." -Sev 'Info'
}
