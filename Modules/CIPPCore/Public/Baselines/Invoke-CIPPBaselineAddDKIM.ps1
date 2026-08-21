function Invoke-CIPPBaselineAddDKIM {
    <#
    .SYNOPSIS
        AddDKIM executor: creates missing DKIM configs and enables disabled ones.
    .DESCRIPTION
        Two bulk batches, the classic's: New-DkimSigningConfig (2048-bit, enabled) for
        domains with no config, Set-DkimSigningConfig enabled for configs that exist
        disabled. Partial failures log and continue; a batch where everything failed throws
        so the run reports the failure honestly.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $ToCreate = @($Current.domainsToCreate | Where-Object { $_ })
    $ToEnable = @($Current.domainsToEnable | Where-Object { $_ })
    if ($ToCreate.Count -eq 0 -and $ToEnable.Count -eq 0) { return }

    $Requests = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($Domain in $ToCreate) {
        $Requests.Add(@{ CmdletInput = @{ CmdletName = 'New-DkimSigningConfig'; Parameters = @{ KeySize = 2048; DomainName = "$Domain"; Enabled = $true } } })
    }
    foreach ($Domain in $ToEnable) {
        $Requests.Add(@{ CmdletInput = @{ CmdletName = 'Set-DkimSigningConfig'; Parameters = @{ Identity = "$Domain"; Enabled = $true } } })
    }

    $Results = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($Requests) -useSystemMailbox $true
    $Errors = @($Results | Where-Object { $_.error })
    foreach ($ErrorResult in $Errors) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "DKIM write failed: $(Get-NormalizedError -Message $ErrorResult.error)" -Sev 'Error'
    }
    if ($Errors.Count -ge $Requests.Count) { throw "Every DKIM write failed for $TenantFilter - see the log for the first error." }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "DKIM: created $($ToCreate.Count) config(s), enabled $($ToEnable.Count)." -Sev 'Info'
}
