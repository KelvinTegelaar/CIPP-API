function Get-CIPPBaselineDevicePrepGroup {
    <#
    .SYNOPSIS
        Resolves the DevicePrepProfile device security group by name prefix.
    .DESCRIPTION
        Shared by the prepare hook and the executor so both act on the same group. Matches are
        ordered exact-name first, then by displayName and id, because Graph returns them in no
        guaranteed order. Returns $null when nothing matches.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$GroupName,
        [Parameter(Mandatory = $true)]$TenantFilter
    )

    $EscapedName = $GroupName -replace "'", "''"
    $GroupFilter = [System.Uri]::EscapeDataString("startsWith(displayName,'$EscapedName') and mailEnabled eq false and securityEnabled eq true")
    $MatchedGroups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName&`$filter=$GroupFilter" -tenantid $TenantFilter |
            Where-Object { $_.id } |
            Sort-Object -Property @{ Expression = { "$($_.displayName)" -ne $GroupName } }, displayName, id)
    if ($MatchedGroups.Count -eq 0) { return $null }
    if ($MatchedGroups.Count -gt 1) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "DevicePrepProfile: Multiple groups found matching '$GroupName', using '$($MatchedGroups[0].displayName)' ($($MatchedGroups[0].id))." -Sev 'Warning'
    }
    $MatchedGroups[0]
}
