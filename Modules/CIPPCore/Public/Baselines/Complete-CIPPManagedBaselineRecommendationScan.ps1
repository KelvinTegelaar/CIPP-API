function Complete-CIPPManagedBaselineRecommendationScan {
    <#
    .SYNOPSIS
        Closes a recommendations scan: removes what the scan no longer found and writes the totals.
    .DESCRIPTION
        Rows of an earlier scan that this scan did not write again are removed, which is how a
        resolved finding leaves the list. Counts what is new and what was resolved since the scan
        before. Does nothing when a newer scan of the tenant has started in the meantime.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Partition,
        [Parameter(Mandatory = $true)][string]$ScanId
    )

    $Table = Get-CippTable -tablename 'BaselineRecommendations'
    $Rows = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$(ConvertTo-CIPPODataFilterValue -Value $Partition)'")
    $Scan = $Rows.Where({ $_.RowKey -eq 'scan' }, 'First')[0]
    if (-not $Scan -or "$($Scan.ScanId)" -ne $ScanId) { return }

    $Stale = @($Rows.Where({ $_.RowKey -ne 'scan' -and "$($_.ScanId)" -ne $ScanId }) | Select-Object -Property PartitionKey, RowKey)
    if ($Stale.Count -gt 0) { Remove-CIPPAzDataTableEntity -Force @Table -Entity $Stale }

    $Current = @($Rows.Where({ $_.RowKey -ne 'scan' -and "$($_.ScanId)" -eq $ScanId }))
    $Findings = @($Current.Where({ "$($_.Status)" -in @('Recommended', 'Covered by a baseline') }))
    $Previous = @()
    if ($Scan.PreviousFindings) {
        try { $Previous = @(ConvertFrom-Json -InputObject "$($Scan.PreviousFindings)" -ErrorAction Stop) } catch { $Previous = @() }
    }
    $FindingKeys = @($Findings.RowKey)
    $New = 0
    $Resolved = 0
    if ($Scan.HadPrevious -eq $true) {
        $New = @($FindingKeys.Where({ $_ -notin $Previous })).Count
        $Resolved = @($Previous.Where({ $_ -notin $FindingKeys })).Count
    }

    Add-CIPPAzDataTableEntity @Table -Entity @{
        PartitionKey     = $Partition
        RowKey           = 'scan'
        Status           = 'Finished'
        FinishedAt       = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
        Recommended      = @($Current.Where({ "$($_.Status)" -eq 'Recommended' })).Count
        Covered          = @($Current.Where({ "$($_.Status)" -eq 'Covered by a baseline' })).Count
        Compliant        = @($Current.Where({ "$($_.Status)" -eq 'Compliant' })).Count
        NewFindings      = $New
        ResolvedFindings = $Resolved
        PreviousFindings = ''
    } -OperationType UpsertMerge
}
