function Set-CIPPDBCacheSPOSites {
    <#
    .SYNOPSIS
        Caches per-site SharePoint Online settings for every site collection

    .DESCRIPTION
        Type 'SPOSites': one row per site collection, keyed by site id. The tenant-wide enumeration
        supplies only the site URLs, because it returns defaults for per-site settings such as
        ShowPeoplePickerSuggestionsForGuestUsers. The per-site read (GetSitePropertiesByUrl) supplies
        the row. SharePoint answers each site read in ~0.7 s and serialises the reads inside one
        request, so the URLs fan out as batches of their own task, a few at a time per tenant, and
        Push-StoreSPOSites writes the rows once. Only fields a consumer reads are collected.

    .PARAMETER TenantFilter
        The tenant to cache SharePoint site settings for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $Urls = @(Get-CIPPSPOSite -TenantFilter $TenantFilter -UseCertificate -Properties 'Url' | ForEach-Object { "$($_.Url)" } | Where-Object { $_ })
        if ($Urls.Count -eq 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SPOSites' -Data @() -AddCount -ClearOnEmpty
            return
        }

        $SitesPerBatch = 100
        $TotalBatches = [Math]::Ceiling($Urls.Count / $SitesPerBatch)
        $Batches = for ($i = 0; $i -lt $Urls.Count; $i += $SitesPerBatch) {
            $BatchItem = [PSCustomObject]@{
                FunctionName = 'DBCacheSPOSitesBatch'
                TenantFilter = $TenantFilter
                QueueName    = "SharePoint Sites Batch $($i / $SitesPerBatch + 1)/$TotalBatches - $TenantFilter"
                Urls         = @($Urls[$i..([Math]::Min($i + $SitesPerBatch - 1, $Urls.Count - 1))])
            }
            if ($QueueId) { $BatchItem | Add-Member -NotePropertyName 'QueueId' -NotePropertyValue $QueueId }
            $BatchItem
        }
        if ($QueueId) {
            try { Update-CippQueueEntry -RowKey $QueueId -TotalTasks $TotalBatches -IncrementTotalTasks } catch { Write-Information "Could not update queue $QueueId with SPOSites batches: $($_.Exception.Message)" }
        }

        $null = Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                Batch            = @($Batches)
                OrchestratorName = "SPOSites_$TenantFilter"
                AllowCollision   = $false
                MaxConcurrency   = 2
                SkipLog          = $true
                PostExecution    = @{
                    FunctionName = 'StoreSPOSites'
                    Parameters   = @{ TenantFilter = $TenantFilter; TotalBatches = $TotalBatches }
                }
            })
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Started SharePoint site settings collection across $($Urls.Count) sites in $TotalBatches batches" -sev Debug

    } catch {
        # A tenant with no SharePoint app-only consent answers 401 every run until that changes;
        # record it and move on rather than failing the whole collection for it.
        if ($_.Exception.Data['SPOAccessDenied'] -or $_.Exception.Message -match '\b401\b|unauthorized') {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Skipped SharePoint site cache: $($_.Exception.Message)" -sev Warning
            return
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SharePoint site settings: $($_.Exception.Message)" -sev Error
        throw
    }
}
