function Invoke-CIPPBaselinePhishSimSpoofIntelligence {
    <#
    .SYNOPSIS
        PhishSimSpoofIntelligence executor: aligns the spoof intelligence allow list.
    .DESCRIPTION
        One bulk batch, the classic's: removals first (only when the operator opted into
        strict ownership), then each missing domain added TWICE - once as Internal and once
        as External spoof type, wildcarded to every spoofed user - because simulation
        senders spoof both directions and the classic allowed both.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Missing = @($Current.missingDomains | Where-Object { $_ })
    $RemoveIds = @($Current.extraItemIds | Where-Object { $_ })
    if ($Missing.Count -eq 0 -and $RemoveIds.Count -eq 0) { return }

    $Requests = [System.Collections.Generic.List[hashtable]]::new()
    if ($RemoveIds.Count -gt 0) {
        $Requests.Add(@{ CmdletInput = @{ CmdletName = 'Remove-TenantAllowBlockListSpoofItems'; Parameters = @{ Identity = 'default'; Ids = @($RemoveIds) } } })
    }
    foreach ($Domain in $Missing) {
        foreach ($SpoofType in @('Internal', 'External')) {
            $Requests.Add(@{ CmdletInput = @{ CmdletName = 'New-TenantAllowBlockListSpoofItems'; Parameters = @{
                        Identity = 'default'; Action = 'Allow'; SendingInfrastructure = "$Domain"; SpoofedUser = '*'; SpoofType = $SpoofType
                    } } })
        }
    }

    $Results = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($Requests) -useSystemMailbox $true
    $Errors = @($Results | Where-Object { $_.error })
    foreach ($ErrorResult in $Errors) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Spoof intelligence write failed: $(Get-NormalizedError -Message $ErrorResult.error)" -Sev 'Error'
    }
    if ($Errors.Count -ge $Requests.Count) { throw "Every spoof intelligence write failed for $TenantFilter - see the log for the first error." }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Spoof intelligence: allowed $($Missing.Count) domain(s), removed $($RemoveIds.Count) item(s)." -Sev 'Info'
}
