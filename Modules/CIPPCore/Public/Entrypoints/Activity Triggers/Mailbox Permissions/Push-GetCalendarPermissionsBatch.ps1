function Push-GetCalendarPermissionsBatch {
    <#
    .SYNOPSIS
        Process a batch of calendar permission queries

    .DESCRIPTION
        Queries calendar permissions for a batch of mailboxes

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

        $AllCalendarPermissions = [System.Collections.Generic.List[object]]::new()

        foreach ($MailboxUPN in $Mailboxes) {
            try {
                # Step 1: Get the calendar folder name (locale-specific)
                $GetCalParam = @{Identity = $MailboxUPN; FolderScope = 'Calendar' }
                $CalendarFolder = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderStatistics' -anchor $MailboxUPN -cmdParams $GetCalParam | Select-Object -First 1

                if ($CalendarFolder -and $CalendarFolder.name) {
                    # Step 2: Get calendar permissions using the folder name
                    $CalParam = @{Identity = "$($MailboxUPN):\$($CalendarFolder.name)" }
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
                } else {
                    Write-Information "No calendar folder found for mailbox $MailboxUPN"
                }
            } catch {
                Write-Information "Failed to get calendar permissions for $MailboxUPN : $($_.Exception.Message)"
                # Continue processing other mailboxes
            }
        }

        Write-Information "Completed calendar permissions batch $BatchNumber of $TotalBatches - processed $($Mailboxes.Count) mailboxes: $($AllCalendarPermissions.Count) calendar permissions"

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
