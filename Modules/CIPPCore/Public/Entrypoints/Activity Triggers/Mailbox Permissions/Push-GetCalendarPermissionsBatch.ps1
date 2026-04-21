function Push-GetCalendarPermissionsBatch {
    <#
    .SYNOPSIS
        Process a batch of calendar permission queries

    .DESCRIPTION
        Queries calendar permissions for a batch of mailboxes.
        Uses a folder name cache to avoid the expensive Get-MailboxFolderStatistics call
        on subsequent runs. First run discovers and caches the locale-specific calendar
        folder name; all future runs skip that call entirely (50% fewer Exchange requests).

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
            Write-Host "CAL Cached Folders count is $($CachedFolders.count)"
        } catch {
            Write-Information "Could not load folder name cache for $TenantFilter, will discover all folder names"
        }

        $CacheHits = 0
        $CacheMisses = 0
        $NewCacheEntries = [System.Collections.Generic.List[hashtable]]::new()
        $AllCalendarPermissions = [System.Collections.Generic.List[object]]::new()

        foreach ($MailboxUPN in $Mailboxes) {
            try {
                # Check cache for folder name
                $FolderName = $CachedFolders[$MailboxUPN]

                if (-not $FolderName) {
                    # Cache miss — discover the locale-specific calendar folder name
                    $CacheMisses++
                    $GetCalParam = @{Identity = $MailboxUPN; FolderScope = 'Calendar' }
                    $CalendarFolder = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderStatistics' -anchor $MailboxUPN -cmdParams $GetCalParam | Select-Object -First 1

                    if ($CalendarFolder -and $CalendarFolder.name) {
                        $FolderName = $CalendarFolder.name
                        # Queue for cache write
                        $NewCacheEntries.Add(@{
                                PartitionKey = $TenantFilter
                                RowKey       = $MailboxUPN
                                FolderName   = $FolderName
                            })
                    } else {
                        Write-Information "No calendar folder found for mailbox $MailboxUPN"
                        continue
                    }
                } else {
                    $CacheHits++
                }

                # Get calendar permissions using the folder name
                $CalParam = @{Identity = "$($MailboxUPN):\$($FolderName)" }
                $CalendarPermissions = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderPermission' -anchor $MailboxUPN -cmdParams $CalParam -UseSystemMailbox $true

                # Normalize the results
                foreach ($Perm in $CalendarPermissions) {
                    $AllCalendarPermissions.Add([PSCustomObject]@{
                            id           = [guid]::NewGuid().ToString()
                            Identity     = $Perm.Identity
                            User         = $Perm.User
                            AccessRights = $Perm.AccessRights
                            FolderName   = $Perm.FolderName
                        })
                }
            } catch {
                Write-Information "Failed to get calendar permissions for $MailboxUPN : $($_.Exception.Message)"
                # Continue processing other mailboxes
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

        Write-Information "Completed calendar permissions batch $BatchNumber of $TotalBatches - processed $($Mailboxes.Count) mailboxes: $($AllCalendarPermissions.Count) permissions (cache hits: $CacheHits, misses: $CacheMisses)"

        # Return results grouped by command type for consistency with mailbox permissions
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
