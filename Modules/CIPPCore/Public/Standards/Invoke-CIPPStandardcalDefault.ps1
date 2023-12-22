function Invoke-CIPPStandardcalDefault {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate) {
        $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox'
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Started setting default calendar permissions for $($Mailboxes.Count) mailboxes." -sev Info

        # BRRRRRRRRRR
        $global:UserSuccesses = 0
        $Mailboxes | ForEach-Object -ThrottleLimit 25 -Parallel {
            Import-Module CIPPcore
            $Tenant = $Using:Tenant
            $Settings = $Using:Settings
            $Mailbox = $_
            try {
                $GetRetryCount = 0
                
                do {
                    # Get all calendars for the mailbox, retry if it fails
                    try {
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxFolderStatistics' -cmdParams @{identity = $Mailbox.UserPrincipalName; FolderScope = 'Calendar' } -Anchor $Mailbox.UserPrincipalName | 
                            # Set permissions for each calendar found
                            Where-Object { $_.FolderType -eq 'Calendar' } | ForEach-Object {
                                $SetRetryCount = 0
                                do {
                                    try {
                                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxFolderPermission' -cmdparams @{Identity = "$($Mailbox.UserPrincipalName):$($_.FolderId)"; User = 'Default'; AccessRights = $Settings.permissionlevel } -Anchor $Mailbox.UserPrincipalName 
                                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set default folder permission for $($Mailbox.UserPrincipalName):\$($_.Name) to $($Settings.permissionlevel)" -sev Debug 
                                        $Success = $true
                                    } catch {
                                        # Set part
                                        Start-Sleep -Milliseconds 250
                                        $SetRetryCount++
                                    }
                                } Until ($SetRetryCount -ge 3 -or $Success -eq $true)
                            }
                            $Success = $true
                            $global:UserSuccesses++
                        } catch {
                            # Get part
                            Start-Sleep -Milliseconds 250
                            $GetRetryCount++
                        }

                    } until ($GetRetryCount -ge 3 -or $Success -eq $true)
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set default calendar permissions for $($Mailbox.UserPrincipalName). Error: $($_.exception.message)" -sev Error
                }        
            }
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Done setting default calendar permissions for $global:UserSuccesses out of $($Mailboxes.Count) mailboxes." -sev Info

        }
    }