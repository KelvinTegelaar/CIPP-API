function Invoke-CIPPStandardcalDefault {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings, $QueueItem)

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
                            New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxFolderPermission' -cmdparams @{Identity = "$($Mailbox.UserPrincipalName):$($_.FolderId)"; User = 'Default'; AccessRights = $Settings.permissionlevel } -Anchor $Mailbox.UserPrincipalName
                            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set default folder permission for $($Mailbox.UserPrincipalName):\$($_.Name) to $($Settings.permissionlevel)" -sev Debug
                            $SuccessCounter++
                        } catch {
                            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                            Write-Host "Setting cal failed: $ErrorMessage"
                            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set default calendar permissions for $($Mailbox.UserPrincipalName). Error: $ErrorMessage" -sev Error
                        }
                    }
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set default calendar permissions for $($Mailbox.UserPrincipalName). Error: $ErrorMessage" -sev Error
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
