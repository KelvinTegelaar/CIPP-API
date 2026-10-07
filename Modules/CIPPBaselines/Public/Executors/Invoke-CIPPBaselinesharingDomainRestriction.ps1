function Invoke-CIPPBaselinesharingDomainRestriction {
    <#
    .SYNOPSIS
        sharingDomainRestriction executor: writes the sharing domain restriction mode and
        list.
    .DESCRIPTION
        One app-only PATCH: the mode plus - for the list modes - the matching domain list,
        the classic's write.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Mode = "$($Remediate.mode)"
    if ($Mode -notin @('none', 'allowList', 'blockList')) { return }
    $Body = @{ sharingDomainRestrictionMode = $Mode }
    if ($Mode -ne 'none') {
        $Domains = @("$($Remediate.domains)".Split(',').Trim() | Where-Object { $_ })
        if ($Domains.Count -eq 0) { return }
        if ($Mode -eq 'allowList') { $Body['sharingAllowedDomainList'] = @($Domains) } else { $Body['sharingBlockedDomainList'] = @($Domains) }
    }
    $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -type PATCH -body ($Body | ConvertTo-Json) -AsApp $true -ContentType 'application/json'
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Set the sharing domain restriction mode to $Mode." -Sev 'Info'
}
