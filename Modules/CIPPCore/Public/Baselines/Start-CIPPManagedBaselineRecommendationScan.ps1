function Start-CIPPManagedBaselineRecommendationScan {
    <#
    .SYNOPSIS
        Starts a recommendations scan of one tenant against CyberDrain's recommendation list.
    .DESCRIPTION
        Everything that is recommended comes from the list the Managed Baselines service returns,
        so there is no scan without a valid key. Each entry is { id, standard, variables, title,
        reason, impact }. CIPP only compares: one compare per entry is queued, and nothing about
        the tenant is sent anywhere. Nothing is downloaded or imported. Conditional Access is not
        part of the scan: an entry for a template is skipped. A finding that was there in the
        scan before keeps the date it was first seen.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]$Tenant,
        [string]$StartedBy
    )

    $TenantFilter = "$($Tenant.defaultDomainName)"
    $Partition = "$($Tenant.customerId)"
    if (-not $TenantFilter -or -not $Partition) { throw [System.ArgumentException]::new('Choose the tenant to scan.') }
    if (-not $PSCmdlet.ShouldProcess($TenantFilter, 'Start a recommendations scan')) { return }

    $List = Invoke-ManagedBaselinesRequest -Path 'recommendations'

    $Table = Get-CippTable -tablename 'BaselineRecommendations'
    $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
    $Existing = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$(ConvertTo-CIPPODataFilterValue -Value $Partition)'")
    $Scan = $Existing.Where({ $_.RowKey -eq 'scan' }, 'First')[0]
    # A scan takes minutes; one still open after six hours lost its run.
    if ("$($Scan.Status)" -eq 'Running' -and [int64]($Scan.StartedAt ?? 0) -gt ($Now - 21600)) {
        throw [System.ArgumentException]::new("A scan of $TenantFilter is still running.")
    }

    $FirstSeen = @{}
    $Previous = [System.Collections.Generic.List[string]]::new()
    foreach ($Row in $Existing) {
        if ("$($Row.Status)" -notin @('Recommended', 'Covered by a baseline') -or $Row.RowKey -eq 'scan') { continue }
        $Previous.Add("$($Row.RowKey)")
        if ($Row.FirstSeen) { $FirstSeen["$($Row.RowKey)"] = [int64]$Row.FirstSeen }
    }

    $CoveredStandards = @{}
    try {
        foreach ($WorkItem in @(Get-CIPPBaselineWorkItems -TenantFilter $TenantFilter)) {
            if ($WorkItem.BaseName) { $CoveredStandards["$($WorkItem.BaseName)"] = $true }
        }
    } catch {
        Write-Information "Recommendations scan: the baselines covering $TenantFilter could not be resolved: $($_.Exception.Message)"
    }

    $Known = @{}
    foreach ($Definition in @(Get-CIPPBaselineDefinition)) {
        if ($Definition.name -and $Definition.disabled -ne $true) { $Known["$($Definition.name)"] = $true }
    }
    $Entries = [System.Collections.Generic.List[object]]::new()
    $SeenIds = @{}
    $Skipped = 0
    foreach ($Entry in @($List.recommendations)) {
        $Id = "$($Entry.id ?? $Entry.standard)" -replace '[^\w-]', ''
        if (-not $Entry.standard -or -not $Id -or $SeenIds.ContainsKey($Id)) { continue }
        if (-not $Known.ContainsKey("$($Entry.standard)") -or $Entry.template -or "$($Entry.standard)" -eq 'ConditionalAccessTemplate') {
            $Skipped++
            continue
        }
        $SeenIds[$Id] = $true
        $Entries.Add([PSCustomObject]@{ Id = $Id; Entry = $Entry })
    }

    $ScanId = [string](New-Guid).Guid
    Add-CIPPAzDataTableEntity @Table -Entity @{
        PartitionKey     = $Partition
        RowKey           = 'scan'
        TenantFilter     = $TenantFilter
        Status           = 'Running'
        ScanId           = $ScanId
        StartedAt        = $Now
        StartedBy        = "$StartedBy"
        ListVersion      = "$($List.version)"
        Total            = $Entries.Count
        Skipped          = $Skipped
        HadPrevious      = ($null -ne $Scan -and [int64]($Scan.FinishedAt ?? 0) -gt 0)
        PreviousFindings = [string](ConvertTo-Json -Compress -InputObject @($Previous))
        Error            = ''
    } -OperationType UpsertMerge

    if ($Entries.Count -eq 0) {
        Complete-CIPPManagedBaselineRecommendationScan -Partition $Partition -ScanId $ScanId
        return [PSCustomObject]@{ Total = 0 }
    }

    $Queue = New-CippQueueEntry -Name "Recommendations scan ($($Entries.Count) recommendations) - $TenantFilter" -Reference 'ManagedBaselineRecommendations' -TotalTasks $Entries.Count
    $Batch = foreach ($Item in $Entries) {
        $Entry = $Item.Entry
        [PSCustomObject]@{
            FunctionName = 'CIPPManagedBaselineRecommendationCollect'
            Partition    = $Partition
            ScanId       = $ScanId
            TenantFilter = $TenantFilter
            Id           = $Item.Id
            Standard     = "$($Entry.standard)"
            Variables    = $Entry.variables
            Title        = "$($Entry.title)"
            Reason       = "$($Entry.reason)"
            Impact       = "$($Entry.impact)"
            InBaseline   = $CoveredStandards.ContainsKey("$($Entry.standard)")
            FirstSeen    = [int64]($FirstSeen["rec-$($Item.Id)"] ?? 0)
            QueueId      = $Queue.RowKey
            QueueName    = ('{0} - {1}' -f $Item.Id, $TenantFilter)
        }
    }
    $Orchestration = @{
        Batch            = @($Batch)
        OrchestratorName = "ManagedBaselineRecommendations_$Partition"
        SkipLog          = $true
        PostExecution    = @{
            FunctionName = 'CIPPManagedBaselineRecommendationComplete'
            Parameters   = @{ Partition = $Partition; ScanId = $ScanId }
        }
    }
    try {
        $null = Start-CIPPOrchestrator -InputObject ([PSCustomObject]$Orchestration)
    } catch {
        Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = $Partition; RowKey = 'scan'; Status = 'Failed'; Error = "The scan could not be started: $($_.Exception.Message)" } -OperationType UpsertMerge
        throw
    }

    [PSCustomObject]@{ Total = $Entries.Count }
}
