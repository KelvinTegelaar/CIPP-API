function Invoke-CIPPStandardcalDefault {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) calDefault
    .SYNOPSIS
        (Label) Set Sharing Level for Default calendar
    .DESCRIPTION
        (Helptext) Sets the default sharing level for the default calendar, for all users
        (DocsDescription) Sets the default sharing level for the default calendar for all users in the tenant. You can read about the different sharing levels [here.](https://learn.microsoft.com/en-us/powershell/module/exchange/set-mailboxfolderpermission?view=exchange-ps#-accessrights)
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Configures how much calendar information employees share by default with colleagues, balancing collaboration needs with privacy. This setting determines whether others can see meeting details, free/busy times, or just availability, helping optimize scheduling while protecting sensitive meeting information.
        DISABLEDFEATURES
            {"report":true,"warn":true,"remediate":false}
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"label":"Select Sharing Level","name":"standards.calDefault.permissionLevel","options":[{"label":"Owner - The user can create, read, edit, and delete all items in the folder, and create subfolders. The user is both folder owner and folder contact.","value":"Owner"},{"label":"Publishing Editor - The user can create, read, edit, and delete all items in the folder, and create subfolders.","value":"PublishingEditor"},{"label":"Editor - The user can create items in the folder. The contents of the folder do not appear.","value":"Editor"},{"label":"Publishing Author.  The user can read, create all items/subfolders. Can modify and delete only items they create.","value":"PublishingAuthor"},{"label":"Author - The user can create and read items, and modify and delete items that they create.","value":"Author"},{"label":"Non Editing Author - The user has full read access and create items. Can can delete only own items.","value":"NonEditingAuthor"},{"label":"Reviewer - The user can read all items in the folder.","value":"Reviewer"},{"label":"Contributor - The user can create items and folders.","value":"Contributor"},{"label":"Availability Only - Indicates that the user can view only free/busy time within the calendar.","value":"AvailabilityOnly"},{"label":"Limited Details - The user can view free/busy time within the calendar and the subject and location of appointments.","value":"LimitedDetails"},{"label":"None - The user has no permissions on the folder.","value":"none"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2023-04-27
        POWERSHELLEQUIVALENT
            Set-MailboxFolderPermission
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings, $QueueItem)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'calDefault'
    $TestResult = Test-CIPPStandardLicense -StandardName 'calDefault' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    # Get permissionLevel value using null-coalescing operator
    $permissionLevel = $Settings.permissionLevel.value ?? $Settings.permissionLevel

    # Input validation
    if ([string]::IsNullOrWhiteSpace($permissionLevel) -or $permissionLevel -eq 'Select a value') {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'calDefault: Invalid permissionLevel parameter set' -sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        $UpdateDB = $false
        try {
            # Get calendar permissions from cache - this contains the calendar Identity we need
            $CalendarPermissions = New-CIPPDbRequest -TenantFilter $Tenant -Type 'CalendarPermissions'

            if (-not $CalendarPermissions) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No cached calendar permissions found. Please ensure the mailbox cache has been populated.' -sev Error
                return
            }

            # Filter to only Default user permissions that don't match target level
            $DefaultPermissions = $CalendarPermissions | Where-Object { $_.User -eq 'Default' }
            $NeedsUpdate = $DefaultPermissions | Where-Object {
                $currentRights = if ($_.AccessRights -is [array]) { $_.AccessRights -join ',' } else { $_.AccessRights }
                $currentRights -ne $permissionLevel
            }

            $TotalCalendars = $DefaultPermissions.Count
            $CalendarsToUpdate = $NeedsUpdate.Count

            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Found $TotalCalendars calendars. $CalendarsToUpdate need permission update to $permissionLevel." -sev Info

            if ($CalendarsToUpdate -eq 0) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All calendars already have the correct default permission level.' -sev Info
                return
            }

            # Set permissions for each calendar that needs updating
            $SuccessCounter = 0
            $ErrorCounter = 0

            foreach ($Calendar in $NeedsUpdate) {
                try {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxFolderPermission' -cmdParams @{
                        Identity     = $Calendar.Identity
                        User         = 'Default'
                        AccessRights = $permissionLevel
                    }
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set default calendar permission for $($Calendar.Identity) to $permissionLevel" -sev Debug
                    $SuccessCounter++
                    $UpdateDB = $true
                } catch {
                    $ErrorCounter++
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set calendar permission for $($Calendar.Identity): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                }
            }

            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set default calendar permissions for $SuccessCounter calendars. $ErrorCounter failed." -sev Info

            # Refresh calendar permissions cache after remediation only if changes were made
            if ($UpdateDB) {
                try {
                    Set-CIPPDBCacheMailboxes -TenantFilter $Tenant
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to refresh mailbox cache after remediation: $($_.Exception.Message)" -sev Warning
                }
            }

        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set default calendar permissions. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

}
