function Get-CIPPMailboxPermissionReport {
    <#
    .SYNOPSIS
        Generates a mailbox permission report from the CIPP Reporting database

    .DESCRIPTION
        Retrieves mailbox permissions for a tenant and formats them into a report.
        Default view shows permissions per mailbox. Use -ByUser to pivot by user.

    .PARAMETER TenantFilter
        The tenant to generate the report for

    .PARAMETER ByUser
        If specified, groups results by user instead of by mailbox

    .EXAMPLE
        Get-CIPPMailboxPermissionReport -TenantFilter 'contoso.onmicrosoft.com'
        Shows which users have access to each mailbox

    .EXAMPLE
        Get-CIPPMailboxPermissionReport -TenantFilter 'contoso.onmicrosoft.com' -ByUser
        Shows what mailboxes each user has access to
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [switch]$ByUser
    )

    try {
        Write-LogMessage -API 'MailboxPermissionReport' -tenant $TenantFilter -message 'Generating mailbox permission report' -sev Info

        # Handle AllTenants
        if ($TenantFilter -eq 'AllTenants') {
            # Get all tenants that have mailbox data
            $AllMailboxItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'Mailboxes'
            $Tenants = @($AllMailboxItems | Where-Object { $_.RowKey -ne 'Mailboxes-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $TenantResults = Get-CIPPMailboxPermissionReport -TenantFilter $Tenant -ByUser:$ByUser
                    foreach ($Result in $TenantResults) {
                        # Add Tenant property to each result
                        $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'MailboxPermissionReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults
        }

        # Get mailboxes from reporting DB
        $MailboxItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes'
        if (-not $MailboxItems) {
            throw 'No mailbox data found in reporting database. Sync the mailbox permissions first. '
        }

        # Get the most recent mailbox cache timestamp
        $MailboxCacheTimestamp = ($MailboxItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp

        # Parse mailbox data and create lookup by UPN, ID, and ExternalDirectoryObjectId (case-insensitive)
        $MailboxLookup = @{}
        $MailboxByIdLookup = @{}
        $MailboxByExternalIdLookup = @{}
        foreach ($Item in $MailboxItems | Where-Object { $_.RowKey -ne 'Mailboxes-Count' }) {
            $Mailbox = $Item.Data | ConvertFrom-Json
            if ($Mailbox.UPN) {
                $MailboxLookup[$Mailbox.UPN.ToLower()] = $Mailbox
            }
            if ($Mailbox.primarySmtpAddress) {
                $MailboxLookup[$Mailbox.primarySmtpAddress.ToLower()] = $Mailbox
            }
            if ($Mailbox.Id) {
                $MailboxByIdLookup[$Mailbox.Id] = $Mailbox
            }
            if ($Mailbox.ExternalDirectoryObjectId) {
                $MailboxByExternalIdLookup[$Mailbox.ExternalDirectoryObjectId] = $Mailbox
            }
        }

        # Get mailbox permissions from reporting DB
        $PermissionItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxPermissions'
        if (-not $PermissionItems) {
            throw 'No mailbox permission data found in reporting database. Run a scan first.'
        }

        # Get the most recent permission cache timestamp
        $PermissionCacheTimestamp = ($PermissionItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp

        # Parse all permissions
        $AllPermissions = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in $PermissionItems | Where-Object { $_.RowKey -ne 'MailboxPermissions-Count' }) {
            $Permissions = $Item.Data | ConvertFrom-Json
            foreach ($Permission in $Permissions) {
                # Skip SELF permissions and inherited deny permissions
                if ($Permission.User -eq 'NT AUTHORITY\SELF' -or $Permission.Deny -eq $true) {
                    continue
                }

                # Get mailbox info - try multiple match strategies like CustomDataSync does
                $Mailbox = $null
                if ($Permission.Identity) {
                    # Try UPN/primarySmtpAddress lookup (case-insensitive)
                    $Mailbox = $MailboxLookup[$Permission.Identity.ToLower()]

                    # If not found, try ExternalDirectoryObjectId lookup
                    if (-not $Mailbox) {
                        $Mailbox = $MailboxByExternalIdLookup[$Permission.Identity]
                    }

                    # If not found, try ID lookup
                    if (-not $Mailbox) {
                        $Mailbox = $MailboxByIdLookup[$Permission.Identity]
                    }
                }

                if (-not $Mailbox) {
                    Write-Verbose "No mailbox found for Identity: $($Permission.Identity)"
                    continue
                }

                $AllPermissions.Add([PSCustomObject]@{
                        MailboxUPN         = if ($Mailbox.UPN) { $Mailbox.UPN } elseif ($Mailbox.primarySmtpAddress) { $Mailbox.primarySmtpAddress } else { $Permission.Identity }
                        MailboxDisplayName = $Mailbox.displayName
                        MailboxType        = $Mailbox.recipientTypeDetails
                        User               = $Permission.User
                        UserKey            = if ($Permission.User -match '@') { $Permission.User.ToLower() } else { $Permission.User }
                        AccessRights       = ($Permission.AccessRights -join ', ')
                        IsInherited        = $Permission.IsInherited
                        Deny               = $Permission.Deny
                    })
            }
        }

        if ($AllPermissions.Count -eq 0) {
            Write-LogMessage -API 'MailboxPermissionReport' -tenant $TenantFilter -message 'No mailbox permissions found (excluding SELF)' -sev Debug
            Write-Information -Message 'No mailbox permissions found (excluding SELF)'
            return @()
        }

        # Format results based on grouping preference
        if ($ByUser) {
            # Group by user - calculate which mailboxes each user has access to
            # Use UserKey for grouping to handle case-insensitive email addresses
            $Report = $AllPermissions | Group-Object -Property UserKey | ForEach-Object {
                $UserKey = $_.Name
                $UserDisplay = $_.Group[0].User # Use original User value for display

                # Look up the user's mailbox type using multi-strategy approach
                $UserMailbox = $null
                if ($UserDisplay) {
                    # Try UPN/primarySmtpAddress lookup (case-insensitive)
                    $UserMailbox = $MailboxLookup[$UserDisplay.ToLower()]

                    # If not found, try ExternalDirectoryObjectId lookup
                    if (-not $UserMailbox) {
                        $UserMailbox = $MailboxByExternalIdLookup[$UserDisplay]
                    }

                    # If not found, try ID lookup
                    if (-not $UserMailbox) {
                        $UserMailbox = $MailboxByIdLookup[$UserDisplay]
                    }
                }
                $UserMailboxType = if ($UserMailbox) { $UserMailbox.recipientTypeDetails } else { 'Unknown' }

                # Build detailed permissions list with mailbox and access rights
                $PermissionDetails = @($_.Group | ForEach-Object {
                        [PSCustomObject]@{
                            Mailbox      = $_.MailboxDisplayName
                            MailboxUPN   = $_.MailboxUPN
                            AccessRights = $_.AccessRights
                        }
                    })

                [PSCustomObject]@{
                    User                     = $UserDisplay
                    UserMailboxType          = $UserMailboxType
                    MailboxCount             = $_.Count
                    Permissions              = $PermissionDetails
                    Tenant                   = $TenantFilter
                    MailboxCacheTimestamp    = $MailboxCacheTimestamp
                    PermissionCacheTimestamp = $PermissionCacheTimestamp
                }
            } | Sort-Object User
        } else {
            # Default: Group by mailbox
            $Report = $AllPermissions | Group-Object -Property MailboxUPN | ForEach-Object {
                $MailboxUPN = $_.Name
                $MailboxInfo = $_.Group[0]

                # Build detailed permissions list with user and access rights
                $PermissionDetails = @($_.Group | ForEach-Object {
                        [PSCustomObject]@{
                            User         = $_.User
                            AccessRights = $_.AccessRights
                        }
                    })

                [PSCustomObject]@{
                    MailboxUPN               = $MailboxUPN
                    MailboxDisplayName       = $MailboxInfo.MailboxDisplayName
                    MailboxType              = $MailboxInfo.MailboxType
                    PermissionCount          = $_.Count
                    Permissions              = $PermissionDetails
                    Tenant                   = $TenantFilter
                    MailboxCacheTimestamp    = $MailboxCacheTimestamp
                    PermissionCacheTimestamp = $PermissionCacheTimestamp
                }
            } | Sort-Object MailboxDisplayName
        }

        Write-LogMessage -API 'MailboxPermissionReport' -tenant $TenantFilter -message "Generated report with $($Report.Count) entries" -sev Debug
        return $Report

    } catch {
        Write-LogMessage -API 'MailboxPermissionReport' -tenant $TenantFilter -message "Failed to generate mailbox permission report: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw "Failed to generate mailbox permission report: $($_.Exception.Message)"
    }
}
