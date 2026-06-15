function Get-CIPPCalendarPermissionReport {
    <#
    .SYNOPSIS
        Generates a calendar permission report from the CIPP Reporting database

    .DESCRIPTION
        Retrieves calendar permissions for a tenant and formats them into a report.
        Default view shows permissions per calendar. Use -ByUser to pivot by user.

    .PARAMETER TenantFilter
        The tenant to generate the report for

    .PARAMETER ByUser
        If specified, groups results by user instead of by calendar

    .EXAMPLE
        Get-CIPPCalendarPermissionReport -TenantFilter 'contoso.onmicrosoft.com'
        Shows which users have access to each calendar

    .EXAMPLE
        Get-CIPPCalendarPermissionReport -TenantFilter 'contoso.onmicrosoft.com' -ByUser
        Shows what calendars each user has access to
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [switch]$ByUser
    )

    try {
        # Handle AllTenants
        if ($TenantFilter -eq 'AllTenants') {
            # Get all tenants that have calendar data
            $AllCalendarItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'CalendarPermissions'
            $Tenants = @($AllCalendarItems | Where-Object { $_.RowKey -ne 'CalendarPermissions-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $TenantResults = Get-CIPPCalendarPermissionReport -TenantFilter $Tenant -ByUser:$ByUser
                    foreach ($Result in $TenantResults) {
                        # Add Tenant property to each result
                        $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'CalendarPermissionReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults
        }

        # Get mailboxes from reporting DB
        $MailboxItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_.RowKey -ne 'Mailboxes-Count' }
        if (-not $MailboxItems) {
            throw 'No mailbox data found in reporting database. Sync the mailbox permissions first.'
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

        # Get calendar permissions from reporting DB
        $PermissionItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'CalendarPermissions'
        if (-not $PermissionItems) {
            throw 'No calendar permission data found in reporting database. Run a scan first.'
        }

        # Get the most recent permission cache timestamp
        $PermissionCacheTimestamp = ($PermissionItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp

        # Parse all permissions
        $AllPermissions = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in $PermissionItems | Where-Object { $_.RowKey -ne 'CalendarPermissions-Count' }) {
            $Permission = $Item.Data | ConvertFrom-Json

            # Skip Default and Anonymous permissions as they're standard and not typically relevant
            if ($Permission.User -in @('Default', 'Anonymous', 'NT AUTHORITY\SELF')) {
                continue
            }

            # Extract the mailbox identifier from Identity (format: "mailbox-id:\Calendar" or "mailbox-upn:\Calendar")
            # The Identity can contain either a GUID, UPN, or alias before the colon-backslash separator
            $IdentityParts = $Permission.Identity -split ':\\'
            if ($IdentityParts.Count -lt 1) {
                Write-Verbose "Invalid Identity format: $($Permission.Identity)"
                continue
            }
            $MailboxIdentifier = $IdentityParts[0]

            # Get mailbox info - try multiple match strategies
            $Mailbox = $null

            # Try UPN/primarySmtpAddress lookup (case-insensitive)
            $Mailbox = $MailboxLookup[$MailboxIdentifier.ToLower()]

            # If not found, try ExternalDirectoryObjectId lookup
            if (-not $Mailbox) {
                $Mailbox = $MailboxByExternalIdLookup[$MailboxIdentifier]
            }

            # If not found, try ID lookup
            if (-not $Mailbox) {
                $Mailbox = $MailboxByIdLookup[$MailboxIdentifier]
            }

            if (-not $Mailbox) {
                Write-Verbose "No mailbox found for Identity: $MailboxIdentifier"
                continue
            }

            $AllPermissions.Add([PSCustomObject]@{
                    MailboxUPN         = if ($Mailbox.UPN) { $Mailbox.UPN } elseif ($Mailbox.primarySmtpAddress) { $Mailbox.primarySmtpAddress } else { $MailboxIdentifier }
                    MailboxDisplayName = $Mailbox.displayName
                    MailboxType        = $Mailbox.recipientTypeDetails
                    User               = $Permission.User
                    UserKey            = if ($Permission.User -match '@') { $Permission.User.ToLower() } else { $Permission.User }
                    AccessRights       = ($Permission.AccessRights -join ', ')
                    FolderName         = $Permission.FolderName
                })
        }

        if ($AllPermissions.Count -eq 0) {
            Write-LogMessage -API 'CalendarPermissionReport' -tenant $TenantFilter -message 'No calendar permissions found (excluding Default/Anonymous)' -sev Debug
            Write-Information -Message 'No calendar permissions found (excluding Default/Anonymous)'
            return @()
        }

        # Format results based on grouping preference
        if ($ByUser) {
            # Group by user - calculate which calendars each user has access to
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

                # Build detailed permissions list with calendar and access rights
                $PermissionDetails = @($_.Group | ForEach-Object {
                        [PSCustomObject]@{
                            Calendar     = $_.MailboxDisplayName
                            CalendarUPN  = $_.MailboxUPN
                            AccessRights = $_.AccessRights
                            FolderName   = $_.FolderName
                        }
                    })

                [PSCustomObject]@{
                    User                     = $UserDisplay
                    UserMailboxType          = $UserMailboxType
                    CalendarCount            = $_.Count
                    Permissions              = $PermissionDetails
                    Tenant                   = $TenantFilter
                    MailboxCacheTimestamp    = $MailboxCacheTimestamp
                    PermissionCacheTimestamp = $PermissionCacheTimestamp
                }
            } | Sort-Object User
        } else {
            # Default: Group by calendar
            $Report = $AllPermissions | Group-Object -Property MailboxUPN | ForEach-Object {
                $CalendarUPN = $_.Name
                $CalendarInfo = $_.Group[0]

                # Build detailed permissions list with user and access rights
                $PermissionDetails = @($_.Group | ForEach-Object {
                        [PSCustomObject]@{
                            User         = $_.User
                            AccessRights = $_.AccessRights
                            FolderName   = $_.FolderName
                        }
                    })

                [PSCustomObject]@{
                    CalendarUPN              = $CalendarUPN
                    CalendarDisplayName      = $CalendarInfo.MailboxDisplayName
                    CalendarType             = $CalendarInfo.MailboxType
                    FolderName               = $CalendarInfo.FolderName
                    PermissionCount          = $_.Count
                    Permissions              = $PermissionDetails
                    Tenant                   = $TenantFilter
                    MailboxCacheTimestamp    = $MailboxCacheTimestamp
                    PermissionCacheTimestamp = $PermissionCacheTimestamp
                }
            } | Sort-Object CalendarDisplayName
        }

        Write-LogMessage -API 'CalendarPermissionReport' -tenant $TenantFilter -message "Generated report with $($Report.Count) entries" -sev Debug
        return $Report

    } catch {
        Write-LogMessage -API 'CalendarPermissionReport' -tenant $TenantFilter -message "Failed to generate calendar permission report: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw "Failed to generate calendar permission report: $($_.Exception.Message)"
    }
}
