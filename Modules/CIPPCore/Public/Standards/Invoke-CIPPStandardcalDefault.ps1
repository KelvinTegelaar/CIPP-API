function Invoke-CIPPStandardcalDefault {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate) {
        $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox'
        foreach ($Mailbox in $Mailboxes) {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxFolderStatistics' -cmdParams @{identity = $Mailbox.UserPrincipalName; FolderScope = 'Calendar' } -Anchor $Mailbox.UserPrincipalName | Where-Object { $_.FolderType -eq 'Calendar' } | ForEach-Object {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxFolderPermission' -cmdparams @{Identity = "$($Mailbox.UserPrincipalName):$($_.FolderId)"; User = 'Default'; AccessRights = $Settings.permissionlevel } -Anchor $Mailbox.UserPrincipalName 
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Set default folder permission for $($Mailbox.UserPrincipalName):\$($_.Name) to $($Settings.permissionlevel)" -sev Info
                }
            }
            catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set default calendar permissions for $($Mailbox.UserPrincipalName). Error: $($_.exception.message)" -sev Error
            }
            
        }
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Done setting default calendar permissions.' -sev Info

    }

}
