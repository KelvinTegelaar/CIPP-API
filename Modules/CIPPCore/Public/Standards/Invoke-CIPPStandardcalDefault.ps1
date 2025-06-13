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

    # Get permissionLevel value using null-coalescing operator
    $permissionLevel = $Settings.permissionLevel.value ?? $Settings.permissionLevel

    # Input validation
    if ([string]::IsNullOrWhiteSpace($permissionLevel) -or $permissionLevel -eq 'Select a value') {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'calDefault: Invalid permissionLevel parameter set' -sev Error
        Return
    }

    If ($Settings.remediate -eq $true) {
        $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' | Sort-Object UserPrincipalName
        $TotalMailboxes = $Mailboxes.Count
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Started setting default calendar permissions for $($TotalMailboxes) mailboxes." -sev Info

        # Retrieve the last run status
        $LastRunTable = Get-CIPPTable -Table StandardsLastRun
        $Filter = "RowKey eq 'calDefaults' and PartitionKey eq '{0}'" -f $tenant
        $LastRun = Get-CIPPAzDataTableEntity @LastRunTable -Filter $Filter

        $startIndex = 0
        if ($LastRun -and $LastRun.processedMailboxes -lt $LastRun.totalMailboxes ) {
            $startIndex = $LastRun.processedMailboxes
        }

        $SuccessCounter = if ($startIndex -eq 0) { 0 } else { [int64]$LastRun.currentSuccessCount }
        $processedMailboxes = $startIndex
        $Mailboxes = $Mailboxes[$startIndex..($TotalMailboxes - 1)]
        Write-Host "CalDefaults Starting at index $startIndex"
        Write-Host "CalDefaults success counter starting at $SuccessCounter"
        Write-Host "CalDefaults Processing $($Mailboxes.Count) mailboxes"
        $Mailboxes | ForEach-Object {
            $Mailbox = $_
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxFolderStatistics' -cmdParams @{identity = $Mailbox.UserPrincipalName; FolderScope = 'Calendar' } -Anchor $Mailbox.UserPrincipalName | Where-Object { $_.FolderType -eq 'Calendar' } |
                    ForEach-Object {
                        try {
                            New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxFolderPermission' -cmdParams @{Identity = "$($Mailbox.UserPrincipalName):$($_.FolderId)"; User = 'Default'; AccessRights = $permissionLevel } -Anchor $Mailbox.UserPrincipalName
                            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set default folder permission for $($Mailbox.UserPrincipalName):\$($_.Name) to $permissionLevel" -sev Debug
                            $SuccessCounter++
                        } catch {
                            $ErrorMessage = Get-CippException -Exception $_
                            Write-Host "Setting cal failed: $ErrorMessage"
                            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set default calendar permissions for $($Mailbox.UserPrincipalName). Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                        }
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set default calendar permissions for $($Mailbox.UserPrincipalName). Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                }
                $processedMailboxes++
                if ($processedMailboxes % 25 -eq 0) {
                    $LastRun = @{
                        RowKey              = 'calDefaults'
                        PartitionKey        = $Tenant
                        totalMailboxes      = $TotalMailboxes
                        processedMailboxes  = $processedMailboxes
                        currentSuccessCount = $SuccessCounter
                    }
                    Add-CIPPAzDataTableEntity @LastRunTable -Entity $LastRun -Force
                    Write-Host "Processed $processedMailboxes mailboxes"
                }
            }

            $LastRun = @{
                RowKey              = 'calDefaults'
                PartitionKey        = $Tenant
                totalMailboxes      = $TotalMailboxes
                processedMailboxes  = $processedMailboxes
                currentSuccessCount = $SuccessCounter
            }
            Add-CIPPAzDataTableEntity @LastRunTable -Entity $LastRun -Force

            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set default calendar permissions for $SuccessCounter out of $TotalMailboxes mailboxes." -sev Info
        }
    }
