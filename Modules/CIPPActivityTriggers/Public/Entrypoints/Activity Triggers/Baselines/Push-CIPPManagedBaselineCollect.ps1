function Push-CIPPManagedBaselineCollect {
    <#
    .SYNOPSIS
        Durable activity: compare one standard against one tenant for a custom managed baseline request.
    .DESCRIPTION
        One part of the snapshot a custom request sends to CyberDrain. Grades the standard
        against CIPP's own default settings in the engine's compare-only mode, so nothing is
        written to alignment or history, then stores the redacted result as one row of the
        request's collection. A standard that needs a template, or a value only a person can
        choose, is recorded as 'Needs a choice' without reading anything from the tenant.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $Status = 'No Data'
    $Current = $null
    $DiffersOn = [System.Collections.Generic.List[string]]::new()
    try {
        $Grade = Get-CIPPBaselineStandardGrade -TenantFilter "$($Item.TenantFilter)" -Standard "$($Item.Standard)"
        $Definition = $Grade.Definition
        if ($Grade.Status -eq 'Drift' -or $Grade.Status -eq 'Compliant') {
            $Current = Protect-CIPPManagedBaselineSnapshot -Value $Grade.CurrentValue -TenantIdentifiers @($Item.TenantIdentifiers) -Definition $Definition
            foreach ($Difference in @($Grade.Diff)) {
                if (-not $Difference.Property) { continue }
                $Property = "$(Protect-CIPPManagedBaselineSnapshot -Value "$($Difference.Property)" -TenantIdentifiers @($Item.TenantIdentifiers) -Definition $Definition)"
                if (-not $DiffersOn.Contains($Property)) { $DiffersOn.Add($Property) }
            }
        }
        $Status = $Grade.Status
    } catch {
        $Status = 'No Data'
        Write-Information "Managed baseline snapshot: $($Item.Standard) on $($Item.TenantFilter) could not be compared: $($_.Exception.Message)"
    } finally {
        $CurrentJson = ''
        if ($null -ne $Current) {
            $CurrentJson = ConvertTo-Json -Compress -Depth 100 -InputObject $Current
            # One table property holds 32K characters; a value that large is not a setting.
            if ($CurrentJson.Length -gt 30000) { $CurrentJson = '"<too large to send>"' }
        }
        $Table = Get-CippTable -tablename 'ManagedBaselineCollection'
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = "$($Item.RequestId)"
            RowKey       = "$($Item.Standard)"
            Status       = $Status
            InBaseline   = [bool]$Item.InBaseline
            Current      = $CurrentJson
            DiffersOn    = [string](ConvertTo-Json -Compress -InputObject @($DiffersOn))
        } -Force
        if ($Item.QueueId) {
            $null = Update-CippQueueEntry -RowKey $Item.QueueId -Status 'Running' -Name $Item.QueueName
        }
    }
}
