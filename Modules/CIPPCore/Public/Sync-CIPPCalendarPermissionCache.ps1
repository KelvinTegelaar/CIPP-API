function Sync-CIPPCalendarPermissionCache {
    <#
    .SYNOPSIS
        Synchronize calendar permission changes to the cached reporting database

    .DESCRIPTION
        Updates the cached calendar permissions in the reporting database when permissions are
        added or removed via CIPP, keeping the cache in sync with actual permissions.

    .PARAMETER TenantFilter
        The tenant domain or GUID

    .PARAMETER MailboxIdentity
        The mailbox identity (UPN or email)

    .PARAMETER FolderName
        The calendar folder name

    .PARAMETER User
        The user being granted or removed permissions

    .PARAMETER Permissions
        The permission level being granted

    .PARAMETER Action
        Whether to 'Add' or 'Remove' the permission

    .PARAMETER CacheContext
        Optional hashtable shared across calls in one request. The tenant's mailbox lookups and cached
        calendar permission rows are loaded into it once, instead of once per permission change.

    .EXAMPLE
        Sync-CIPPCalendarPermissionCache -TenantFilter 'contoso.com' -MailboxIdentity 'user@contoso.com' -FolderName 'Calendar' -User 'guest@contoso.com' -Permissions 'Editor' -Action 'Add'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$MailboxIdentity,

        [Parameter(Mandatory = $true)]
        [string]$FolderName,

        [Parameter(Mandatory = $true)]
        [string]$User,

        [Parameter(Mandatory = $false)]
        [string]$Permissions,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Add', 'Remove')]
        [string]$Action,

        [Parameter(Mandatory = $false)]
        [hashtable]$CacheContext
    )

    try {
        $CalendarIdentity = "$MailboxIdentity`:\$FolderName"
        # Bulk callers share one context per request so the tenant's cache is read once, not per grant
        $Context = $CacheContext ?? @{}

        if (-not $Context.Mailboxes -and ($Action -eq 'Remove' -or $User -match '@')) {
            $ByAddress = @{}
            $ById = @{}
            $ByExternalId = @{}
            foreach ($Item in Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_.RowKey -ne 'Mailboxes-Count' }) {
                $Mailbox = $Item.Data | ConvertFrom-Json
                $Info = @{
                    UPN                       = if ($Mailbox.UPN) { $Mailbox.UPN } else { $Mailbox.primarySmtpAddress }
                    Id                        = $Mailbox.Id
                    ExternalDirectoryObjectId = $Mailbox.ExternalDirectoryObjectId
                    DisplayName               = $Mailbox.displayName
                }
                if ($Mailbox.UPN) { $ByAddress[$Mailbox.UPN.ToLower()] = $Info }
                if ($Mailbox.primarySmtpAddress) { $ByAddress[$Mailbox.primarySmtpAddress.ToLower()] = $Info }
                if ($Mailbox.Id) { $ById[$Mailbox.Id] = $Mailbox.UPN }
                if ($Mailbox.ExternalDirectoryObjectId) { $ByExternalId[$Mailbox.ExternalDirectoryObjectId] = $Mailbox.UPN }
            }
            $Context.Mailboxes = @{ ByAddress = $ByAddress; ById = $ById; ByExternalId = $ByExternalId }
        }

        # Resolve user to display name if a UPN was provided
        # Calendar permissions use display names, not UPNs
        $UserToCache = $User
        if ($User -match '@') {
            $Resolved = $Context.Mailboxes.ByAddress[$User.ToLower()].DisplayName
            if ($Resolved) {
                $UserToCache = $Resolved
                Write-Information "Resolved $User to display name: $UserToCache" -InformationAction Continue
            }
        }

        if ($Action -eq 'Add') {
            # Create calendar permission object in the same format as cached permissions
            $PermissionObject = [PSCustomObject]@{
                id           = [guid]::NewGuid().ToString()
                Identity     = $CalendarIdentity
                User         = $UserToCache
                AccessRights = $Permissions
                FolderName   = $FolderName
            }

            # Add to cache using Append to not clear existing entries
            $PermissionObject | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CalendarPermissions' -Append
            # The shared row list no longer matches the table, so reload it on the next removal
            $Context.Remove('CalendarPermissionRows')

            Write-LogMessage -API 'CalendarPermissionCache' -tenant $TenantFilter `
                -message "Added calendar permission cache entry: $UserToCache on $CalendarIdentity with $Permissions" -sev Debug

        } else {
            # Remove from cache - need to find the item by Identity and User combination
            try {
                $Mailboxes = $Context.Mailboxes

                # Get all possible identifiers for the target mailbox
                # Callers such as ExecModifyCalPerms pass the Entra object id, but cached rows are keyed by UPN
                $ResolvedUPN = $Mailboxes.ByExternalId[$MailboxIdentity] ?? $Mailboxes.ById[$MailboxIdentity]
                $TargetMailboxInfo = $Mailboxes.ByAddress[($ResolvedUPN ?? $MailboxIdentity).ToLower()]
                $PossibleIdentities = @($MailboxIdentity)
                if ($TargetMailboxInfo) {
                    if ($TargetMailboxInfo.Id) { $PossibleIdentities += $TargetMailboxInfo.Id }
                    if ($TargetMailboxInfo.ExternalDirectoryObjectId) { $PossibleIdentities += $TargetMailboxInfo.ExternalDirectoryObjectId }
                    if ($TargetMailboxInfo.UPN) { $PossibleIdentities += $TargetMailboxInfo.UPN }
                }

                # Build all possible calendar identities (combining each mailbox identifier with folder name)
                $PossibleCalendarIdentities = $PossibleIdentities | ForEach-Object { "$_`:\$FolderName" }

                # Read and parse all CalendarPermissions for this tenant once per context
                if ($null -eq $Context.CalendarPermissionRows) {
                    $Table = Get-CippTable -tablename 'CippReportingDB'
                    $Filter = "PartitionKey eq '{0}' and RowKey ge 'CalendarPermissions-' and RowKey lt 'CalendarPermissions0'" -f $TenantFilter
                    $Rows = [System.Collections.Generic.List[object]]::new()
                    foreach ($CachedPerm in Get-CIPPAzDataTableEntity @Table -Filter $Filter) {
                        # Skip the count row and entries with null or empty Data
                        if ($CachedPerm.RowKey -eq 'CalendarPermissions-Count' -or [string]::IsNullOrEmpty($CachedPerm.Data)) { continue }
                        $Rows.Add([PSCustomObject]@{ RowKey = $CachedPerm.RowKey; Data = $CachedPerm.Data | ConvertFrom-Json })
                    }
                    $Context.CalendarPermissionRows = $Rows
                }

                # Find the specific permission entry that matches on Identity (flexible) and User
                $Match = $Context.CalendarPermissionRows | Where-Object { $PossibleCalendarIdentities -contains $_.Data.Identity -and $_.Data.User -eq $User } | Select-Object -First 1
                if ($Match) {
                    # Extract ItemId from RowKey (format: "Type-ItemId")
                    Write-Information "Removing calendar permission cache entry: $User on $CalendarIdentity (matched via $($Match.Data.Identity))" -InformationAction Continue
                    $ItemId = $Match.RowKey -replace '^CalendarPermissions-', ''
                    Remove-CIPPDbItem -TenantFilter $TenantFilter -Type 'CalendarPermissions' -ItemId $ItemId
                    $null = $Context.CalendarPermissionRows.Remove($Match)

                    Write-Information "Removed calendar permission cache entry: $User on $CalendarIdentity" -InformationAction Continue
                    Write-LogMessage -API 'CalendarPermissionCache' -tenant $TenantFilter `
                        -message "Removed calendar permission cache entry: $User on $CalendarIdentity" -sev Debug
                }
            } catch {
                Write-LogMessage -API 'CalendarPermissionCache' -tenant $TenantFilter `
                    -message "Failed to remove calendar permission cache entry: $($_.Exception.Message)" -sev Warning
                Write-Information "Failed to remove calendar permission cache entry: $($_.Exception.Message)" -InformationAction Continue
            }
        }
    } catch {
        Write-LogMessage -API 'CalendarPermissionCache' -tenant $TenantFilter `
            -message "Failed to sync calendar permission cache: $($_.Exception.Message)" -sev Warning
        # Don't throw - cache sync failures shouldn't break the main operation
    }
}
