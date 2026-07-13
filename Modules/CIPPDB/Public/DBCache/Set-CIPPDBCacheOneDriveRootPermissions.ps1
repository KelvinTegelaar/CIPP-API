function Set-CIPPDBCacheOneDriveRootPermissions {
    <#
    .SYNOPSIS
        Caches OneDrive root permissions for every personal site in a tenant.

    .DESCRIPTION
        Self-contained cache writer: enumerates personal sites via paginated Graph getAllSites,
        fans out batched collection activities (20 sites each), and aggregates results in
        Push-StoreOneDriveRootPermissions (PostExecution).

        One row per OneDrive site in OneDriveRootPermissions with permissionsJson (compressed grant
        array string), nullable hasNonStandardAccess, and collectionStatus (Full | Skipped).

        Does not read OneDriveUsage or other CIPPDB caches. Requires SharePoint/OneDrive license
        (Test-CIPPStandardLicense -Preset SharePoint); unlicensed tenants exit before enumeration.
        Scheduling via CIPPDBCacheTypes.json is deferred — manual test:
        Invoke-ExecCIPPDBCache?TenantFilter={tenant}&Name=OneDriveRootPermissions

        Site enumeration dedupes getAllSites results by siteId before batching. Empty tenants write
        an empty cache directly (PostExecution is skipped when there are zero batches).

        PostExecution passes ExpectedSiteCount; Push-StoreOneDriveRootPermissions throws without writing
        if flattened row count does not match (prevents partial replace-mode wipe). Skipped site rows
        are merged with prior Full cache data when available (merge-on-Skip) so transient failures
        do not overwrite good grant data.

        Owner resolution uses drive.owner (not Owners group or OneDriveUsage). permissionsJson grant
        paths: SiteAdmin, SiteRoleGroup, WebRoleAssignment, LibraryRoleAssignment, DriveRootGrant,
        DriveRootLink. Groups are stored as principals without Entra expansion.

        Consumer limitations: grant paths != effective access; unprovisioned OneDrives absent;
        Skipped sites without a prior Full row have empty permissionsJson; merge-on-Skip may
        restore prior Full data after transient failures; count DriveRootLink entries by distinct
        permissionId (named recipients produce multiple grant rows per link); child folder/file
        sharing is out of scope (SharePointSharingLinks cache).

    .PARAMETER TenantFilter
        Tenant to cache OneDrive root permissions for

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
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'OneDriveRootPermissionsCache' -TenantFilter $TenantFilter -Preset SharePoint -SkipLog
        if ($LicenseCheck -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have SharePoint/OneDrive license, skipping OneDrive root permissions cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Starting OneDrive root permissions collection' -sev Debug

        $RawSites = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/getAllSites?`$filter=isPersonalSite eq true&`$select=id,webUrl,displayName" -tenantid $TenantFilter -asapp $true)

        $SiteById = @{}
        foreach ($Site in $RawSites) {
            if ($Site.id) { $SiteById[$Site.id] = $Site }
        }
        $Sites = @($SiteById.Values)
        $ExpectedSiteCount = $Sites.Count

        if ($ExpectedSiteCount -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No personal sites found; writing empty OneDriveRootPermissions cache' -sev Debug
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OneDriveRootPermissions' -Data @() -AddCount
            return
        }

        $Batches = [System.Collections.Generic.List[object]]::new()
        $TotalBatches = [Math]::Ceiling($Sites.Count / $BatchSize)
        for ($i = 0; $i -lt $Sites.Count; $i += $BatchSize) {
            $BatchSites = $Sites[$i..[Math]::Min($i + $BatchSize - 1, $Sites.Count - 1)]
            $BatchNumber = [Math]::Floor($i / $BatchSize) + 1
            $SiteSeeds = foreach ($Site in $BatchSites) {
                [PSCustomObject]@{
                    id            = $Site.id
                    webUrl        = $Site.webUrl
                    displayName   = $Site.displayName
                }
            }
            $BatchItem = [PSCustomObject]@{
                FunctionName = 'DBCacheOneDriveRootPermissionsBatch'
                TenantFilter = $TenantFilter
                QueueName    = "OneDrive Root Permissions Batch $BatchNumber/$TotalBatches - $TenantFilter"
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
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not update queue $QueueId with OneDrive root permission batch tasks: $($_.Exception.Message)" -sev Warning
            }
        }

        $InputObject = [PSCustomObject]@{
            Batch            = @($Batches)
            OrchestratorName = "OneDriveRootPermissions_$TenantFilter"
            PostExecution    = @{
                FunctionName = 'StoreOneDriveRootPermissions'
                Parameters   = @{
                    TenantFilter      = $TenantFilter
                    ExpectedSiteCount = $ExpectedSiteCount
                }
            }
        }

        $null = Start-CIPPOrchestrator -InputObject $InputObject
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Started OneDrive root permissions collection across $ExpectedSiteCount sites in $($Batches.Count) batches" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to start OneDrive root permissions collection: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
