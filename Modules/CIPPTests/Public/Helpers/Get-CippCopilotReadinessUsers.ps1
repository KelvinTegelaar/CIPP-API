function Get-CippCopilotReadinessUsers {
    <#
    .SYNOPSIS
        The enabled users with an enabled service plan, and those with Microsoft Office enabled, read once for the
        CopilotReadiness suite instead of once per test.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Tenant)

    if ($script:CippCopilotReadinessUsers.Tenant -eq $Tenant) { return $script:CippCopilotReadinessUsers }

    $Seen = $false
    $Licensed = [System.Collections.Generic.List[object]]::new()
    $OfficeLicensed = [System.Collections.Generic.List[object]]::new()
    Get-CIPPTestData -TenantFilter $Tenant -Type 'Users' -Fields 'userPrincipalName', 'displayName', 'accountEnabled', 'assignedPlans' -Stream | ForEach-Object {
        $Seen = $true
        if (-not $_.userPrincipalName -or $_.accountEnabled -ne $true) { return }
        if ($_.assignedPlans.Where({ $_.capabilityStatus -eq 'Enabled' }, 'First').Count) {
            $Licensed.Add([pscustomobject]@{ userPrincipalName = $_.userPrincipalName })
        }
        if ($_.assignedPlans.Where({ $_.service -eq 'MicrosoftOffice' -and $_.capabilityStatus -eq 'Enabled' }, 'First').Count) {
            $OfficeLicensed.Add([pscustomobject]@{ userPrincipalName = $_.userPrincipalName; displayName = $_.displayName })
        }
    }
    [pscustomobject]@{ Tenant = $Tenant; Seen = $Seen; Licensed = $Licensed; OfficeLicensed = $OfficeLicensed }
}
