using namespace System.Net

Function Invoke-ExecModifyMBPerms {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME-message 'Accessed this API' -Sev 'Debug'

    $Username = $request.body.userID
    $Tenantfilter = $request.body.tenantfilter
    $Permissions = $request.body.permissions

    if ($username -eq $null) { exit }

    $userid = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($username)" -tenantid $Tenantfilter).id
    $Results = [System.Collections.ArrayList]::new()

    # Convert permissions to array format if it's an object with numeric keys
    if ($Permissions -is [PSCustomObject]) {
        if ($Permissions.PSObject.Properties.Name -match '^\d+$') {
            $Permissions = $Permissions.PSObject.Properties.Value
        }
        else {
            $Permissions = @($Permissions)
        }
    }

    foreach ($Permission in $Permissions) {
        $PermissionLevels = $Permission.PermissionLevel
        $Modification = $Permission.Modification
        $AutoMap = if ($Permission.PSObject.Properties.Name -contains 'AutoMap') { $Permission.AutoMap } else { $true }

        # Handle multiple permission levels separated by commas
        if ($PermissionLevels -like "*,*") {
            $PermissionLevelArray = $PermissionLevels -split ',' | ForEach-Object { $_.Trim() }
        }
        else {
            $PermissionLevelArray = @($PermissionLevels.Trim())
        }

        # Handle UserID as array of objects or single value
        $TargetUsers = if ($Permission.UserID -is [array]) {
            $Permission.UserID | ForEach-Object { $_.value }
        }
        else {
            @($Permission.UserID)
        }

        foreach ($TargetUser in $TargetUsers) {
            foreach ($PermissionLevel in $PermissionLevelArray) {
                try {
                    switch ($PermissionLevel) {
                        'FullAccess' {
                            if ($Modification -eq 'Remove') {
                                $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Remove-mailboxpermission' -cmdParams @{
                                    Identity     = $userid
                                    user         = $TargetUser
                                    accessRights = @('FullAccess')
                                    Confirm      = $false
                                }
                                $null = $results.Add("Removed $($TargetUser) from $($username) Shared Mailbox permissions (FullAccess)")
                            }
                            else {
                                $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Add-MailboxPermission' -cmdParams @{
                                    Identity     = $userid
                                    user         = $TargetUser
                                    accessRights = @('FullAccess')
                                    automapping  = $AutoMap
                                    Confirm      = $false
                                }
                                $null = $results.Add("Granted $($TargetUser) access to $($username) Mailbox (FullAccess) with automapping set to $($AutoMap)")
                            }
                        }
                        'SendAs' {
                            if ($Modification -eq 'Remove') {
                                $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Remove-RecipientPermission' -cmdParams @{
                                    Identity     = $userid
                                    Trustee      = $TargetUser
                                    accessRights = @('SendAs')
                                    Confirm      = $false
                                }
                                $null = $results.Add("Removed $($TargetUser) from $($username) with Send As permissions")
                            }
                            else {
                                $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Add-RecipientPermission' -cmdParams @{
                                    Identity     = $userid
                                    Trustee      = $TargetUser
                                    accessRights = @('SendAs')
                                    Confirm      = $false
                                }
                                $null = $results.Add("Granted $($TargetUser) access to $($username) with Send As permissions")
                            }
                        }
                        'SendOnBehalf' {
                            if ($Modification -eq 'Remove') {
                                $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Set-Mailbox' -cmdParams @{
                                    Identity            = $userid
                                    GrantSendonBehalfTo = @{
                                        '@odata.type' = '#Exchange.GenericHashTable'
                                        remove        = $TargetUser
                                    }
                                    Confirm             = $false
                                }
                                $null = $results.Add("Removed $($TargetUser) from $($username) Send on Behalf Permissions")
                            }
                            else {
                                $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Set-Mailbox' -cmdParams @{
                                    Identity            = $userid
                                    GrantSendonBehalfTo = @{
                                        '@odata.type' = '#Exchange.GenericHashTable'
                                        add           = $TargetUser
                                    }
                                    Confirm             = $false
                                }
                                $null = $results.Add("Granted $($TargetUser) access to $($username) with Send On Behalf Permissions")
                            }
                        }
                        'ReadPermission' {
                            if ($Modification -eq 'Remove') {
                                $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Remove-MailboxPermission' -cmdParams @{
                                    Identity     = $userid
                                    user         = $TargetUser
                                    accessRights = @('ReadPermission')
                                    Confirm      = $false
                                }
                                $null = $results.Add("Removed $($TargetUser) from $($username) Read Permissions")
                            }
                        }
                        'ExternalAccount' {
                            if ($Modification -eq 'Remove') {
                                $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Remove-MailboxPermission' -cmdParams @{
                                    Identity     = $userid
                                    user         = $TargetUser
                                    accessRights = @('ExternalAccount')
                                    Confirm      = $false
                                }
                                $null = $results.Add("Removed $($TargetUser) from $($username) Read Permissions")
                            }
                        }
                        'DeleteItem' {
                            if ($Modification -eq 'Remove') {
                                $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Remove-MailboxPermission' -cmdParams @{
                                    Identity     = $userid
                                    user         = $TargetUser
                                    accessRights = @('DeleteItem')
                                    Confirm      = $false
                                }
                                $null = $results.Add("Removed $($TargetUser) from $($username) Read Permissions")
                            }
                        }
                        'ChangePermission' {
                            if ($Modification -eq 'Remove') {
                                $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Remove-MailboxPermission' -cmdParams @{
                                    Identity     = $userid
                                    user         = $TargetUser
                                    accessRights = @('ChangePermission')
                                    Confirm      = $false
                                }
                                $null = $results.Add("Removed $($TargetUser) from $($username) Read Permissions")
                            }
                        }
                        'ChangeOwner' {
                            if ($Modification -eq 'Remove') {
                                $MailboxPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Remove-MailboxPermission' -cmdParams @{
                                    Identity     = $userid
                                    user         = $TargetUser
                                    accessRights = @('ChangeOwner')
                                    Confirm      = $false
                                }
                                $null = $results.Add("Removed $($TargetUser) from $($username) Read Permissions")
                            }
                        }
                    }
                    Write-LogMessage -headers $Request.Headers -API $APINAME-message "Executed $($PermissionLevel) permission modification for $($TargetUser) on $($username)" -Sev 'Info' -tenant $TenantFilter
                }
                catch {
                    Write-LogMessage -headers $Request.Headers -API $APINAME-message "Could not execute $($PermissionLevel) permission modification for $($TargetUser) on $($username)" -Sev 'Error' -tenant $TenantFilter
                    $null = $results.Add("Could not execute $($PermissionLevel) permission modification for $($TargetUser) on $($username). Error: $($_.Exception.Message)")
                }
            }
        }
    }

    $body = [pscustomobject]@{'Results' = @($results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
