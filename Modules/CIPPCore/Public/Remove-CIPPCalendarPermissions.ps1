function Remove-CIPPCalendarPermissions {
    <#
    .SYNOPSIS
        Remove calendar permissions for a specific user

    .DESCRIPTION
        Removes calendar folder permissions for a user from specified calendars or all calendars they have access to

    .PARAMETER UserToRemove
        The user whose calendar access should be removed

    .PARAMETER CalendarIdentity
        Optional. Specific calendar identity (e.g., "mailbox@domain.com:\Calendar"). If not provided, will query from cache.

    .PARAMETER FolderName
        Optional. Folder name (defaults to "Calendar"). Used with CalendarIdentity or when querying from cache.

    .PARAMETER TenantFilter
        The tenant to operate on

    .PARAMETER UseCache
        If specified, will query cached calendar permissions to find all calendars the user has access to

    .PARAMETER APIName
        API name for logging (defaults to 'Remove Calendar Permissions')

    .PARAMETER Headers
        Headers for logging

    .EXAMPLE
        Remove-CIPPCalendarPermissions -UserToRemove 'user@domain.com' -CalendarIdentity 'mailbox@domain.com:\Calendar' -TenantFilter 'contoso.com'

    .EXAMPLE
        Remove-CIPPCalendarPermissions -UserToRemove 'user@domain.com' -TenantFilter 'contoso.com' -UseCache
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserToRemove,

        [Parameter(Mandatory = $false)]
        [string]$CalendarIdentity,

        [Parameter(Mandatory = $false)]
        [string]$FolderName = 'Calendar',

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [switch]$UseCache,

        [Parameter(Mandatory = $false)]
        [string]$APIName = 'Remove Calendar Permissions',

        [Parameter(Mandatory = $false)]
        $Headers
    )

    try {
        $Results = [System.Collections.Generic.List[string]]::new()

        if ($UseCache) {
            # Get all calendars this user has access to from cache
            try {
                # Resolve user to display name if a UPN was provided
                # Calendar permissions use display names, not UPNs
                $UserToMatch = $UserToRemove
                # Exchange resolves -User by name, which is ambiguous when two recipients share one.
                # Keep a unique id for Exchange; the display name is only for matching the cache.
                $UserIdentifier = $UserToRemove
                if ($UserToRemove -match '@') {
                    # Try to get display name from mailbox cache
                    $MailboxItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_.RowKey -ne 'Mailboxes-Count' }
                    foreach ($Item in $MailboxItems) {
                        $Mailbox = $Item.Data | ConvertFrom-Json
                        if ($Mailbox.UPN -eq $UserToRemove -or $Mailbox.primarySmtpAddress -eq $UserToRemove) {
                            $UserToMatch = $Mailbox.displayName
                            if ($Mailbox.ExternalDirectoryObjectId) { $UserIdentifier = $Mailbox.ExternalDirectoryObjectId }
                            Write-Information "Resolved $UserToRemove to display name: $UserToMatch" -InformationAction Continue
                            break
                        }
                    }
                }

                $CalendarPermissions = Get-CIPPCalendarPermissionReport -TenantFilter $TenantFilter -ByUser | Where-Object { $_.User -eq $UserToMatch }

                if (-not $CalendarPermissions -or $CalendarPermissions.Permissions.Count -eq 0) {
                    $Message = "No calendar permissions found for $UserToRemove in cached data"
                    Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Info' -tenant $TenantFilter
                    return $Message
                }

                # Remove from each calendar
                foreach ($CalPermEntry in $CalendarPermissions.Permissions) {
                    $Folder = if ($CalPermEntry.FolderName) { $CalPermEntry.FolderName } else { 'Calendar' }
                    $CalIdentity = "$($CalPermEntry.CalendarUPN):\$Folder"
                    $CacheIsStale = $false

                    try {
                        $null = Remove-CIPPFolderPermission -TenantFilter $TenantFilter -FolderIdentity $CalIdentity -User $UserIdentifier -AccessRights $CalPermEntry.AccessRights -Anchor $CalPermEntry.CalendarUPN
                        $CacheIsStale = $true

                        $SuccessMsg = "Removed $UserToRemove from calendar $CalIdentity"
                        Write-LogMessage -headers $Headers -API $APIName -message $SuccessMsg -Sev 'Info' -tenant $TenantFilter
                        $Results.Add($SuccessMsg)
                    } catch {
                        # Only drop the cached row when Exchange confirms there is nothing to remove.
                        # Any other failure leaves the permission live, and clearing the cache would
                        # report an offboarded user as having lost access they still have.
                        $CacheIsStale = $_.Exception.Message -match 'UserNotFoundInPermissionEntryException'

                        $ErrorMsg = "Failed to remove $UserToRemove from calendar $($CalPermEntry.CalendarUPN): $($_.Exception.Message)"
                        Write-LogMessage -headers $Headers -API $APIName -message $ErrorMsg -sev 'Warning' -tenant $TenantFilter
                        $Results.Add($ErrorMsg)
                    }

                    if ($CacheIsStale) {
                        try {
                            Sync-CIPPCalendarPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $CalPermEntry.CalendarUPN -FolderName $Folder -User $UserToMatch -Action 'Remove'
                        } catch {
                            Write-Verbose "Failed to sync cache: $_"
                        }
                    }
                }

                $SummaryMsg = "Processed $($CalendarPermissions.CalendarCount) calendar(s) - removed $($Results.Count) permission(s)"
                Write-LogMessage -headers $Headers -API $APIName -message $SummaryMsg -Sev 'Info' -tenant $TenantFilter
                return $Results

            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -headers $Headers -API $APIName -message "Failed to query calendar permissions from cache: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
                throw "Failed to query calendar permissions from cache: $($ErrorMessage.NormalizedError)"
            }
        } else {
            # Remove from specific calendar
            if ([string]::IsNullOrEmpty($CalendarIdentity)) {
                throw 'CalendarIdentity is required when not using cache'
            }

            $MailboxUPN = if ($CalendarIdentity -match '^([^:]+):') { $Matches[1] } else { $CalendarIdentity }
            $Folder = if ($CalendarIdentity -match ':\\(.+)$') { $Matches[1] } else { $FolderName }

            try {
                $null = Remove-CIPPFolderPermission -TenantFilter $TenantFilter -FolderIdentity $CalendarIdentity -User $UserToRemove -Anchor $MailboxUPN

                Sync-CIPPCalendarPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $MailboxUPN -FolderName $Folder -User $UserToRemove -Action 'Remove'

                $SuccessMsg = "Removed $UserToRemove from calendar $CalendarIdentity"
                Write-LogMessage -headers $Headers -API $APIName -message $SuccessMsg -Sev 'Info' -tenant $TenantFilter
                return $SuccessMsg

            } catch {
                # Only drop the cached row when Exchange confirms there is nothing to remove.
                $CacheIsStale = $_.Exception.Message -match 'UserNotFoundInPermissionEntryException'
                if ($CacheIsStale) {
                    try {
                        Sync-CIPPCalendarPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $MailboxUPN -FolderName $Folder -User $UserToRemove -Action 'Remove'
                    } catch {
                        Write-Verbose "Failed to sync cache: $_"
                    }
                }

                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -headers $Headers -API $APIName -message "Failed to remove calendar permission: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
                throw "Failed to remove calendar permission: $($ErrorMessage.NormalizedError)"
            }
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Could not remove calendar permissions for $UserToRemove. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not remove calendar permissions for $UserToRemove. Error: $($ErrorMessage.NormalizedError)"
    }
}
