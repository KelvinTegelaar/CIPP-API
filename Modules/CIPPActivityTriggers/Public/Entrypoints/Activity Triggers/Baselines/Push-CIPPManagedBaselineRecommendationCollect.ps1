function Push-CIPPManagedBaselineRecommendationCollect {
    <#
    .SYNOPSIS
        Durable activity: compare one entry of the recommendation list against one tenant.
    .DESCRIPTION
        Grades the standard with the values from CyberDrain's list in the engine's compare-only
        mode, so nothing is written to alignment or history, and stores the result as one row of
        the tenant's recommendations. The row stays in the partner's own tables, so the current
        value is stored as it is.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $Status = 'No data'
    $Current = $null
    $Differences = @()
    try {
        $Grade = Get-CIPPBaselineStandardGrade -TenantFilter "$($Item.TenantFilter)" -Standard "$($Item.Standard)" -Variables $Item.Variables -SourceTemplate 'Managed baseline recommendations'
        switch ($Grade.Status) {
            'Compliant' { $Status = 'Compliant' }
            'No licence' { $Status = 'No licence' }
            'Drift' { $Status = $Item.InBaseline ? 'Covered by a baseline' : 'Recommended' }
        }
        if ($Grade.Status -in @('Compliant', 'Drift')) {
            $Current = $Grade.CurrentValue
            $Differences = @($Grade.Diff | Where-Object { $_.Property })
        }
    } catch {
        Write-Information "Recommendations scan: $($Item.Id) on $($Item.TenantFilter) could not be compared: $($_.Exception.Message)"
    } finally {
        # One table property holds 32K characters; a value that large is not a setting.
        $CurrentJson = ''
        if ($null -ne $Current) {
            $CurrentJson = ConvertTo-Json -Compress -Depth 100 -InputObject $Current
            if ($CurrentJson.Length -gt 30000) { $CurrentJson = '"<too large to show>"' }
        }
        $DifferencesJson = [string](ConvertTo-Json -Compress -Depth 20 -InputObject @($Differences | Select-Object -Property Property, ExpectedValue, ReceivedValue))
        if ($DifferencesJson.Length -gt 30000) {
            $DifferencesJson = [string](ConvertTo-Json -Compress -InputObject @($Differences | Select-Object -Property Property))
        }
        $VariablesJson = ''
        if ($null -ne $Item.Variables) { $VariablesJson = ConvertTo-Json -Compress -Depth 100 -InputObject $Item.Variables }
        $IsFinding = $Status -in @('Recommended', 'Covered by a baseline')
        $FirstSeen = [int64]($Item.FirstSeen ?? 0)
        if ($FirstSeen -le 0) { $FirstSeen = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds()) }

        $Table = Get-CippTable -tablename 'BaselineRecommendations'
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = "$($Item.Partition)"
            RowKey       = "rec-$($Item.Id)"
            TenantFilter = "$($Item.TenantFilter)"
            ScanId       = "$($Item.ScanId)"
            Standard     = "$($Item.Standard)"
            Title        = "$($Item.Title)"
            Reason       = "$($Item.Reason)"
            Impact       = "$($Item.Impact)"
            Status       = $Status
            Current      = $CurrentJson
            Differences  = $DifferencesJson
            Variables    = $VariablesJson
            FirstSeen    = $IsFinding ? $FirstSeen : [int64]0
        } -Force
        if ($Item.QueueId) {
            $null = Update-CippQueueEntry -RowKey $Item.QueueId -Status 'Running' -Name $Item.QueueName
        }
    }
}
