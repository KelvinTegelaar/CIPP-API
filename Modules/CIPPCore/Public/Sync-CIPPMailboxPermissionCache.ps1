function Sync-CIPPMailboxPermissionCache {
    <#
    .SYNOPSIS
        Synchronize mailbox permission changes to the cached reporting database

    .DESCRIPTION
        Updates the cached mailbox permissions in the reporting database when permissions are
        added or removed via CIPP, keeping the cache in sync with actual permissions.

    .PARAMETER TenantFilter
        The tenant domain or GUID

    .PARAMETER MailboxIdentity
        The mailbox identity (UPN or email)

    .PARAMETER User
        The user/trustee being granted or removed permissions

    .PARAMETER PermissionType
        The type of permission: 'FullAccess', 'SendAs', or 'SendOnBehalf'

    .PARAMETER Action
        Whether to 'Add' or 'Remove' the permission

    .EXAMPLE
        Sync-CIPPMailboxPermissionCache -TenantFilter 'contoso.com' -MailboxIdentity 'mailbox@contoso.com' -User 'user@contoso.com' -PermissionType 'FullAccess' -Action 'Add'

    .EXAMPLE
        Sync-CIPPMailboxPermissionCache -TenantFilter 'contoso.com' -MailboxIdentity 'mailbox@contoso.com' -User 'user@contoso.com' -PermissionType 'SendAs' -Action 'Remove'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$MailboxIdentity,

        [Parameter(Mandatory = $true)]
        [string]$User,

        [Parameter(Mandatory = $true)]
        [ValidateSet('FullAccess', 'SendAs', 'SendOnBehalf')]
        [string]$PermissionType,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Add', 'Remove')]
        [string]$Action
    )

    try {
        if ($Action -eq 'Add') {
            # Create permission object in the same format as cached permissions
            $PermissionObject = [PSCustomObject]@{
                id           = [guid]::NewGuid().ToString()
                Identity     = $MailboxIdentity
                User         = $User
                AccessRights = @($PermissionType)
                IsInherited  = $false
                Deny         = $false
            }

            # Determine which type to use based on permission
            $Type = if ($PermissionType -eq 'SendAs') { 'MailboxPermissions' } else { 'MailboxPermissions' }

            # Add to cache using Append to not clear existing entries
            $PermissionObject | Add-CIPPDbItem -TenantFilter $TenantFilter -Type $Type -Append

            Write-LogMessage -API 'MailboxPermissionCache' -tenant $TenantFilter `
                -message "Added $PermissionType permission cache entry: $User on $MailboxIdentity" -sev Debug

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
                            UPN                       = $Mailbox.UPN
                            Id                        = $Mailbox.Id
                            ExternalDirectoryObjectId = $Mailbox.ExternalDirectoryObjectId
                        }
                    }
                    if ($Mailbox.primarySmtpAddress) {
                        $MailboxLookup[$Mailbox.primarySmtpAddress.ToLower()] = @{
                            UPN                       = if ($Mailbox.UPN) { $Mailbox.UPN } else { $Mailbox.primarySmtpAddress }
                            Id                        = $Mailbox.Id
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

                # Query for all MailboxPermissions for this tenant
                $Filter = "PartitionKey eq '{0}' and RowKey ge 'MailboxPermissions-' and RowKey lt 'MailboxPermissions0'" -f $TenantFilter
                $AllPermissions = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { $_.RowKey -ne 'MailboxPermissions-Count' }

                # Find the specific permission entry that matches
                foreach ($CachedPerm in $AllPermissions) {
                    # Skip entries with null or empty Data
                    if ([string]::IsNullOrEmpty($CachedPerm.Data)) {
                        continue
                    }

                    $PermData = $CachedPerm.Data | ConvertFrom-Json

                    # Match on Identity (flexible), User, and AccessRights
                    if ($PossibleIdentities -contains $PermData.Identity -and
                        $PermData.User -eq $User -and
                        $PermData.AccessRights -contains $PermissionType) {

                        # Extract ItemId from RowKey (format: "Type-ItemId")
                        Write-Information "Removing $PermissionType permission cache entry: $User on $MailboxIdentity (matched via $($PermData.Identity))" -InformationAction Continue
                        $ItemId = $CachedPerm.RowKey -replace '^MailboxPermissions-', ''
                        Remove-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxPermissions' -ItemId $ItemId

                        Write-Information "Removed $PermissionType permission cache entry: $User on $MailboxIdentity" -InformationAction Continue
                        Write-LogMessage -API 'MailboxPermissionCache' -tenant $TenantFilter `
                            -message "Removed $PermissionType permission cache entry: $User on $MailboxIdentity" -sev Debug
                        break
                    }
                }
            } catch {
                Write-LogMessage -API 'MailboxPermissionCache' -tenant $TenantFilter `
                    -message "Failed to remove permission cache entry: $($_.Exception.Message)" -sev Warning
                Write-Information "Failed to remove permission cache entry: $($_.Exception.Message)" -InformationAction Continue
            }
        }
    } catch {
        Write-LogMessage -API 'MailboxPermissionCache' -tenant $TenantFilter `
            -message "Failed to sync permission cache: $($_.Exception.Message)" -sev Warning
        # Don't throw - cache sync failures shouldn't break the main operation
        Write-Information "Failed to sync permission cache: $($_.Exception.Message)" -InformationAction Continue
    }
}
