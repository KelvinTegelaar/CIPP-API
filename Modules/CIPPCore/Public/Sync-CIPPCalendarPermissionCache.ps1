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
        [string]$Action
    )

    try {
        $CalendarIdentity = "$MailboxIdentity`:\$FolderName"

        # Resolve user to display name if a UPN was provided
        # Calendar permissions use display names, not UPNs
        $UserToCache = $User
        if ($User -match '@') {
            # Try to get display name from mailbox cache
            $MailboxItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_.RowKey -ne 'Mailboxes-Count' }
            foreach ($Item in $MailboxItems) {
                $Mailbox = $Item.Data | ConvertFrom-Json
                if ($Mailbox.UPN -eq $User -or $Mailbox.primarySmtpAddress -eq $User) {
                    $UserToCache = $Mailbox.displayName
                    Write-Information "Resolved $User to display name: $UserToCache" -InformationAction Continue
                    break
                }
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

            Write-LogMessage -API 'CalendarPermissionCache' -tenant $TenantFilter `
                -message "Added calendar permission cache entry: $UserToCache on $CalendarIdentity with $Permissions" -sev Debug

        } else {
            # Remove from cache - need to find the item by Identity and User combination
            try {
                $Table = Get-CippTable -tablename 'CippReportingDB'

                # Build mailbox lookup for flexible Identity matching (same as report function)
                $MailboxItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_.RowKey -ne 'Mailboxes-Count' }
                $MailboxLookup = @{}
                $MailboxByIdLookup = @{}
                $MailboxByExternalIdLookup = @{}

                foreach ($Item in $MailboxItems) {
                    $Mailbox = $Item.Data | ConvertFrom-Json
                    if ($Mailbox.UPN) {
                        $MailboxLookup[$Mailbox.UPN.ToLower()] = @{
                            UPN = $Mailbox.UPN
                            Id = $Mailbox.Id
                            ExternalDirectoryObjectId = $Mailbox.ExternalDirectoryObjectId
                        }
                    }
                    if ($Mailbox.primarySmtpAddress) {
                        $MailboxLookup[$Mailbox.primarySmtpAddress.ToLower()] = @{
                            UPN = if ($Mailbox.UPN) { $Mailbox.UPN } else { $Mailbox.primarySmtpAddress }
                            Id = $Mailbox.Id
                            ExternalDirectoryObjectId = $Mailbox.ExternalDirectoryObjectId
                        }
                    }
                    if ($Mailbox.Id) {
                        $MailboxByIdLookup[$Mailbox.Id] = $Mailbox.UPN
                    }
                    if ($Mailbox.ExternalDirectoryObjectId) {
                        $MailboxByExternalIdLookup[$Mailbox.ExternalDirectoryObjectId] = $Mailbox.UPN
                    }
                }

                # Get all possible identifiers for the target mailbox
                $TargetMailboxInfo = $MailboxLookup[$MailboxIdentity.ToLower()]
                $PossibleIdentities = @($MailboxIdentity)
                if ($TargetMailboxInfo) {
                    if ($TargetMailboxInfo.Id) { $PossibleIdentities += $TargetMailboxInfo.Id }
                    if ($TargetMailboxInfo.ExternalDirectoryObjectId) { $PossibleIdentities += $TargetMailboxInfo.ExternalDirectoryObjectId }
                    if ($TargetMailboxInfo.UPN) { $PossibleIdentities += $TargetMailboxInfo.UPN }
                }

                # Build all possible calendar identities (combining each mailbox identifier with folder name)
                $PossibleCalendarIdentities = $PossibleIdentities | ForEach-Object { "$_`:\$FolderName" }

                # Query for all CalendarPermissions for this tenant
                $Filter = "PartitionKey eq '{0}' and RowKey ge 'CalendarPermissions-' and RowKey lt 'CalendarPermissions0'" -f $TenantFilter
                $AllPermissions = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { $_.RowKey -ne 'CalendarPermissions-Count' }

                # Find the specific permission entry that matches
                foreach ($CachedPerm in $AllPermissions) {
                    # Skip entries with null or empty Data
                    if ([string]::IsNullOrEmpty($CachedPerm.Data)) {
                        continue
                    }

                    $PermData = $CachedPerm.Data | ConvertFrom-Json

                    # Match on Identity (flexible) and User
                    if ($PossibleCalendarIdentities -contains $PermData.Identity -and $PermData.User -eq $User) {

                        # Extract ItemId from RowKey (format: "Type-ItemId")
                        Write-Information "Removing calendar permission cache entry: $User on $CalendarIdentity (matched via $($PermData.Identity))" -InformationAction Continue
                        $ItemId = $CachedPerm.RowKey -replace '^CalendarPermissions-', ''
                        Remove-CIPPDbItem -TenantFilter $TenantFilter -Type 'CalendarPermissions' -ItemId $ItemId

                        Write-Information "Removed calendar permission cache entry: $User on $CalendarIdentity" -InformationAction Continue
                        Write-LogMessage -API 'CalendarPermissionCache' -tenant $TenantFilter `
                            -message "Removed calendar permission cache entry: $User on $CalendarIdentity" -sev Debug
                        break
                    }
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
