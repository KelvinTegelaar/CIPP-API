function Set-CIPPDBCacheSharePointPermissions {
    <#
    .SYNOPSIS
        Fans out SharePoint site and document library permission collection, batched by site.

    .DESCRIPTION
        Enumerates every non-personal site in the tenant and starts a child orchestration with one
        activity per batch of 20 sites (Push-DBCacheSharePointPermissionsBatch). A single
        PostExecution (Push-StoreSharePointPermissions) aggregates every batch and writes the
        SharePointPermissions cache once.

        Batching rather than one activity per site: this scan costs roughly ten calls per site plus
        one per library that holds its own permissions, so it is proportional to libraries rather
        than to files. That is orders of magnitude cheaper than the sharing link scan
        (Set-CIPPDBCacheSharePointSharingLinks), which walks every drive's whole file tree and so
        needs a whole activity per site to bound memory.

        Personal sites are excluded - OneDrive permissions are covered by the separate
        OneDriveRootPermissions cache.

    .PARAMETER TenantFilter
        The tenant to cache SharePoint permissions for

    .PARAMETER QueueId
        Optional queue ID for progress tracking
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    $BatchSize = 20

    try {
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'SharePointPermissionsCache' -TenantFilter $TenantFilter -Preset SharePoint -SkipLog
        if ($LicenseCheck -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have a SharePoint license, skipping SharePoint permissions cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Starting SharePoint permissions collection' -sev Debug

        # Personal sites are filtered out here rather than with $filter=isPersonalSite eq false:
        # that filter returns an empty set against getAllSites, so the site list is fetched whole
        # and narrowed locally, the same way the sharing links cache does it.
        $RawSites = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/getAllSites?`$select=id,displayName,name,webUrl,isPersonalSite&`$top=999" -tenantid $TenantFilter -asapp $true)

        # getAllSites can return the same site more than once across pages.
        $SiteById = @{}
        foreach ($Site in $RawSites) {
            if ($Site.id -and -not $Site.isPersonalSite) { $SiteById[$Site.id] = $Site }
        }
        $Sites = @($SiteById.Values)
        $ExpectedSiteCount = $Sites.Count

        if ($ExpectedSiteCount -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No SharePoint sites found; writing empty SharePointPermissions cache' -sev Debug
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointPermissions' -Data @() -AddCount
            return
        }

        $Batches = [System.Collections.Generic.List[object]]::new()
        $TotalBatches = [Math]::Ceiling($Sites.Count / $BatchSize)
        for ($i = 0; $i -lt $Sites.Count; $i += $BatchSize) {
            $BatchSites = $Sites[$i..[Math]::Min($i + $BatchSize - 1, $Sites.Count - 1)]
            $BatchNumber = [Math]::Floor($i / $BatchSize) + 1
            $SiteSeeds = foreach ($Site in $BatchSites) {
                [PSCustomObject]@{
                    id          = $Site.id
                    webUrl      = $Site.webUrl
                    # Left null when the site genuinely has no name - some system sites (the
                    # Search Centre, for one) come back from getAllSites without one. A readable
                    # label is derived from the URL by Invoke-ListSharePointPermissions rather
                    # than stored here, because a URL in a name column renders as a link.
                    displayName = $Site.displayName ?? $Site.name
                }
            }
            $BatchItem = [PSCustomObject]@{
                FunctionName = 'DBCacheSharePointPermissionsBatch'
                TenantFilter = $TenantFilter
                QueueName    = "SharePoint Permissions Batch $BatchNumber/$TotalBatches - $TenantFilter"
                BatchNumber  = $BatchNumber
                TotalBatches = $TotalBatches
                Sites        = @($SiteSeeds)
            }
            if ($QueueId) {
                $BatchItem | Add-Member -NotePropertyName 'QueueId' -NotePropertyValue $QueueId -Force
            }
            [void]$Batches.Add($BatchItem)
        }

        if ($QueueId -and $Batches.Count -gt 0) {
            try {
                Update-CippQueueEntry -RowKey $QueueId -TotalTasks $Batches.Count -IncrementTotalTasks
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not update queue $QueueId with SharePoint permission batch tasks: $($_.Exception.Message)" -sev Warning
            }
        }

        $InputObject = [PSCustomObject]@{
            Batch            = @($Batches)
            OrchestratorName = "SharePointPermissions_$TenantFilter"
            SkipLog          = $true
            PostExecution    = @{
                FunctionName = 'StoreSharePointPermissions'
                Parameters   = @{
                    TenantFilter      = $TenantFilter
                    ExpectedSiteCount = $ExpectedSiteCount
                }
            }
        }

        $null = Start-CIPPOrchestrator -InputObject $InputObject
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Started SharePoint permissions collection across $ExpectedSiteCount sites in $($Batches.Count) batches" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to start SharePoint permissions collection: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
