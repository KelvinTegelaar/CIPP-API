function Invoke-CIPPStandardcalDefault {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate) {
        $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'get-mailbox'
        foreach ($Mailbox in $Mailboxes) {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxFolderStatistics' -cmdParams @{identity = $Mailbox.UserPrincipalName; FolderScope = 'Calendar' } -Anchor $Mailbox.UserPrincipalName | Where-Object { $_.FolderType -eq 'Calendar' } | ForEach-Object {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxFolderPermission' -cmdparams @{Identity = "$($Mailbox.UserPrincipalName):$($_.FolderId)"; User = 'Default'; AccessRights = $setting.permissionlevel } -Anchor $Mailbox.UserPrincipalName 
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Set default folder permission for $($Mailbox.UserPrincipalName):\$($_.Name) to $($setting.permissionlevel)" -sev Error
                }
            }
            catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set default calendar permissions for $($Mailbox.UserPrincipalName). Error: $($_.exception.message)" -sev Error
            }
        
        }
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Done setting default calendar permissions.' -sev Info

    }

}
