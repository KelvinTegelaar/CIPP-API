function Push-GetCalendarPermissionsBatch {
    <#
    .SYNOPSIS
        Process a batch of calendar permission queries

    .DESCRIPTION
        Queries calendar permissions for a batch of mailboxes using bulk Exchange
        requests. Splits into two phases:
          Phase 1: Bulk Get-MailboxFolderStatistics for cache-miss mailboxes
          Phase 2: Bulk Get-MailboxFolderPermission for all mailboxes
        Uses a folder name cache to skip Phase 1 on subsequent runs.

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $Mailboxes = $Item.Mailboxes
    $BatchNumber = $Item.BatchNumber
    $TotalBatches = $Item.TotalBatches

    try {
        Write-Information "Processing calendar permissions batch $BatchNumber of $TotalBatches for tenant $TenantFilter with $($Mailboxes.Count) mailboxes"

        # Load cached calendar folder names for this tenant
        $FolderCacheTable = Get-CippTable -tablename 'CalendarFolderCache'
        $CachedFolders = @{}
        try {
            $CacheEntries = Get-CIPPAzDataTableEntity @FolderCacheTable -Filter "PartitionKey eq '$TenantFilter'"
            foreach ($Entry in $CacheEntries) {
                $CachedFolders[$Entry.RowKey] = $Entry.FolderName
            }
            Write-Information "CAL Cached Folders count is $($CachedFolders.Count)"
        } catch {
            Write-Information "Could not load folder name cache for $TenantFilter, will discover all folder names"
        }

        # Separate mailboxes into cache hits and misses
        $CacheMissMailboxes = [System.Collections.Generic.List[string]]::new()
        $FolderNameMap = @{}

        foreach ($MailboxUPN in $Mailboxes) {
            $FolderName = $CachedFolders[$MailboxUPN]
            if ($FolderName) {
                $FolderNameMap[$MailboxUPN] = $FolderName
            } else {
                $CacheMissMailboxes.Add($MailboxUPN)
            }
        }

        Write-Information "Cache hits: $($FolderNameMap.Count), cache misses: $($CacheMissMailboxes.Count)"

        # Phase 1: Bulk discover calendar folder names for cache misses
        if ($CacheMissMailboxes.Count -gt 0) {
            $FolderStatsRequests = foreach ($MailboxUPN in $CacheMissMailboxes) {
                @{
                    CmdletInput   = @{
                        CmdletName = 'Get-MailboxFolderStatistics'
                        Parameters = @{
                            Identity    = $MailboxUPN
                            FolderScope = 'Calendar'
                        }
                    }
                    OperationGuid = $MailboxUPN
                }
            }

            Write-Information "Phase 1: Bulk Get-MailboxFolderStatistics for $($CacheMissMailboxes.Count) mailboxes"
            $FolderStatsResults = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($FolderStatsRequests)

            $NewCacheEntries = [System.Collections.Generic.List[hashtable]]::new()
            foreach ($Result in $FolderStatsResults) {
                if ($Result.error) {
                    Write-Information "Failed to get folder stats for $($Result.OperationGuid): $($Result.error)"
                    continue
                }
                $MailboxUPN = $Result.OperationGuid
                $FolderName = $Result.name
                if ($MailboxUPN -and $FolderName) {
                    $FolderNameMap[$MailboxUPN] = $FolderName
                    $NewCacheEntries.Add(@{
                            PartitionKey = $TenantFilter
                            RowKey       = $MailboxUPN
                            FolderName   = $FolderName
                        })
                }
            }

            # Persist newly discovered folder names to cache
            if ($NewCacheEntries.Count -gt 0) {
                try {
                    Add-CIPPAzDataTableEntity @FolderCacheTable -Entity $NewCacheEntries -Force
                    Write-Information "Cached $($NewCacheEntries.Count) new calendar folder names for $TenantFilter"
                } catch {
                    Write-Information "Failed to write folder name cache for $TenantFilter : $($_.Exception.Message)"
                }
            }
        }

        # Phase 2: Bulk get calendar permissions for all mailboxes with known folder names
        $PermissionRequests = foreach ($MailboxUPN in $Mailboxes) {
            $FolderName = $FolderNameMap[$MailboxUPN]
            if ($FolderName) {
                @{
                    CmdletInput   = @{
                        CmdletName = 'Get-MailboxFolderPermission'
                        Parameters = @{
                            Identity = "$($MailboxUPN):\$($FolderName)"
                        }
                    }
                    OperationGuid = $MailboxUPN
                }
            } else {
                Write-Information "Skipping $MailboxUPN - no calendar folder name available"
            }
        }

        $AllCalendarPermissions = [System.Collections.Generic.List[object]]::new()

        if ($PermissionRequests) {
            Write-Information "Phase 2: Bulk Get-MailboxFolderPermission for $(@($PermissionRequests).Count) mailboxes"
            $PermissionResults = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($PermissionRequests) -useSystemMailbox $true

            foreach ($Perm in $PermissionResults) {
                if ($Perm.error) {
                    Write-Information "Failed to get calendar permissions for $($Perm.OperationGuid): $($Perm.error)"
                    continue
                }
                $AccessStr = if ($Perm.AccessRights -is [array]) { $Perm.AccessRights -join ',' } else { $Perm.AccessRights }
                $AllCalendarPermissions.Add([PSCustomObject]@{
                        id           = "CAL-$($Perm.Identity)-$($Perm.User)-$AccessStr"
                        Identity     = $Perm.Identity
                        User         = $Perm.User
                        AccessRights = $Perm.AccessRights
                        FolderName   = $Perm.FolderName
                    })
            }
        }

        Write-Information "Completed calendar permissions batch $BatchNumber of $TotalBatches - processed $($Mailboxes.Count) mailboxes: $($AllCalendarPermissions.Count) permissions (cache hits: $($FolderNameMap.Count - $NewCacheEntries.Count), misses: $($CacheMissMailboxes.Count))"

        return @{
            'Get-MailboxFolderPermission' = $AllCalendarPermissions
        }

    } catch {
        $ErrorMsg = "Failed to process calendar permissions batch $BatchNumber of $TotalBatches for tenant $TenantFilter : $($_.Exception.Message)"
        Write-Information "ERROR in Push-GetCalendarPermissionsBatch: $ErrorMsg"
        Write-Information "Stack trace: $($_.ScriptStackTrace)"
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $ErrorMsg -sev Error
        throw $ErrorMsg
    }
}
