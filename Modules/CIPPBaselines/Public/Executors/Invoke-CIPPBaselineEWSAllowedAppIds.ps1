function Invoke-CIPPBaselineEWSAllowedAppIds {
    <#
    .SYNOPSIS
        EWSAllowedAppIds executor: enables EWS and merges the required app IDs into the list.
    .DESCRIPTION
        Set-OrganizationConfig replaces the whole list, so the list is re-read live and the
        write is always current + required. Known-malicious IDs already on the list are
        removed only when removeMaliciousApps is on; otherwise they stay and are reported.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $StateParams = @{}
    $Carried = $Current.stateParams
    $Pairs = if ($Carried -is [System.Collections.IDictionary]) { $Carried.GetEnumerator() } else { $Carried.PSObject.Properties }
    foreach ($Pair in $Pairs) { $StateParams[$Pair.Name] = $Pair.Value }
    $State = Get-CIPPEwsAllowedAppIdState @StateParams

    if ($State.NeedsWrite) {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-OrganizationConfig' -cmdParams @{ EwsEnabled = $true; EwsAllowedAppIDs = ($State.DesiredAppIds -join ',') } -UseSystemMailbox $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "EWS allowed applications: enabled EWS, added $($State.MissingAppIds.Count) app ID(s), list now $($State.DesiredAppIds.Count)." -Sev 'Info'
    }
    $Remaining = @($State.MaliciousAppIdsPresent | Where-Object { $State.DesiredAppIds -contains $_ })
    if ($Remaining.Count -gt 0) {
        throw "Known-malicious app ID(s) $($Remaining -join ', ') are on the EWS allow list. Enable 'Remove known-malicious apps from the list' or remove them manually."
    }
}
