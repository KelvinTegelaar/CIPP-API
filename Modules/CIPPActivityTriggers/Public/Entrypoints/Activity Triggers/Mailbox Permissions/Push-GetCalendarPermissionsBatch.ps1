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
                # Entries predating the FolderType fix can name a subfolder instead of the root,
                # and the name alone cannot say which. Anything unstamped is a miss: Phase 1
                # rediscovers it and overwrites the row, so a poisoned cache self-heals.
                if ($Entry.FolderType -ne 'Calendar') { continue }
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

        # Declared out here because the completion log below reads its count even when Phase 1 is skipped
        $NewCacheEntries = [System.Collections.Generic.List[hashtable]]::new()

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
            $FolderStatsResults = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($FolderStatsRequests) -Select 'Name,FolderType'

            # One call returns EVERY calendar folder flattened under one OperationGuid, so
            # last-wins cached whatever the mailbox listed last - 'United States holidays' for
            # over half a tenant, after which Phase 2 queried that folder and got nothing.
            # FolderType stays English in any mailbox language, same reason
            # Invoke-ListCalendarPermissions uses it. No fallback on purpose: a guess here
            # poisons a cache that never expires.
            foreach ($Result in $FolderStatsResults) {
                if ($Result.error) {
                    Write-Information "Failed to get folder stats for $($Result.OperationGuid): $($Result.error)"
                    continue
                }
                $MailboxUPN = $Result.OperationGuid
                if (-not $MailboxUPN -or -not $Result.Name -or $Result.FolderType -ne 'Calendar') { continue }
                if ($FolderNameMap.ContainsKey($MailboxUPN)) { continue }

                $FolderNameMap[$MailboxUPN] = $Result.Name
                $NewCacheEntries.Add(@{
                        PartitionKey = $TenantFilter
                        RowKey       = $MailboxUPN
                        FolderName   = $Result.Name
                        FolderType   = 'Calendar'
                    })
            }

            # Loud on purpose: if the API stops returning FolderType, every mailbox fails the
            # filter above and the whole type silently collects nothing.
            $NoRootCalendar = $CacheMissMailboxes.Count - $NewCacheEntries.Count
            if ($NoRootCalendar -gt 0) {
                Write-Information "No root calendar folder (FolderType 'Calendar') found for $NoRootCalendar of $($CacheMissMailboxes.Count) cache-miss mailboxes"
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
