using namespace System.Net

function Invoke-ExecModifyMBPerms {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Username = $Request.Body.userID
    $TenantFilter = $Request.Body.tenantFilter
    $Permissions = $Request.Body.permissions

    if ($null -eq $Username) {
        Write-LogMessage -headers $Headers -API $APIName -message 'Username is null' -Sev 'Error'
        return @{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ Results = @('Username is required') }
        }
    }

    $UserId = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)" -tenantid $TenantFilter).id
    $Results = [System.Collections.Generic.List[string]]::new()

    # Convert permissions to array format if it's an object with numeric keys
    if ($Permissions -is [PSCustomObject]) {
        if ($Permissions.PSObject.Properties.Name -match '^\d+$') {
            $Permissions = $Permissions.PSObject.Properties.Value
        } else {
            $Permissions = @($Permissions)
        }
    }

    foreach ($Permission in $Permissions) {
        $PermissionLevels = $Permission.PermissionLevel
        $Modification = $Permission.Modification
        $AutoMap = if ($Permission.PSObject.Properties.Name -contains 'AutoMap') { $Permission.AutoMap } else { $true }

        # Handle multiple permission levels separated by commas
        if ($PermissionLevels -like '*,*') {
            $PermissionLevelArray = $PermissionLevels -split ',' | ForEach-Object { $_.Trim() }
        } else {
            $PermissionLevelArray = @($PermissionLevels.Trim())
        }

        # Handle UserID as array of objects or single value
        $TargetUsers = if ($Permission.UserID -is [array]) {
            $Permission.UserID | ForEach-Object { $_.value }
        } else {
            @($Permission.UserID)
        }

        foreach ($TargetUser in $TargetUsers) {
            foreach ($PermissionLevel in $PermissionLevelArray) {
                try {
                    switch ($PermissionLevel) {
                        'FullAccess' {
                            if ($Modification -eq 'Remove') {
                                $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Remove-MailboxPermission' -cmdParams @{
                                    Identity     = $UserId
                                    User         = $TargetUser
                                    AccessRights = @('FullAccess')
                                    Confirm      = $false
                                }
                                $Results.Add("Removed $($TargetUser) from $($Username) Shared Mailbox permissions (FullAccess)")
                            } else {
                                $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Add-MailboxPermission' -cmdParams @{
                                    Identity     = $UserId
                                    User         = $TargetUser
                                    AccessRights = @('FullAccess')
                                    AutoMapping  = $AutoMap
                                    Confirm      = $false
                                }
                                $Results.Add("Granted $($TargetUser) access to $($Username) Mailbox (FullAccess) with AutoMapping set to $($AutoMap)")
                            }
                        }
                        'SendAs' {
                            if ($Modification -eq 'Remove') {
                                $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Remove-RecipientPermission' -cmdParams @{
                                    Identity     = $UserId
                                    Trustee      = $TargetUser
                                    AccessRights = @('SendAs')
                                    Confirm      = $false
                                }
                                $Results.Add("Removed $($TargetUser) from $($Username) with Send As permissions")
                            } else {
                                $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Add-RecipientPermission' -cmdParams @{
                                    Identity     = $UserId
                                    Trustee      = $TargetUser
                                    AccessRights = @('SendAs')
                                    Confirm      = $false
                                }
                                $Results.Add("Granted $($TargetUser) access to $($Username) with Send As permissions")
                            }
                        }
                        'SendOnBehalf' {
                            if ($Modification -eq 'Remove') {
                                $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{
                                    Identity            = $UserId
                                    GrantSendOnBehalfTo = @{
                                        '@odata.type' = '#Exchange.GenericHashTable'
                                        remove        = $TargetUser
                                    }
                                    Confirm             = $false
                                }
                                $Results.Add("Removed $($TargetUser) from $($Username) Send on Behalf Permissions")
                            } else {
                                $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{
                                    Identity            = $UserId
                                    GrantSendOnBehalfTo = @{
                                        '@odata.type' = '#Exchange.GenericHashTable'
                                        add           = $TargetUser
                                    }
                                    Confirm             = $false
                                }
                                $Results.Add("Granted $($TargetUser) access to $($Username) with Send On Behalf Permissions")
                            }
                        }
                        'ReadPermission' {
                            if ($Modification -eq 'Remove') {
                                $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Remove-MailboxPermission' -cmdParams @{
                                    Identity     = $UserId
                                    User         = $TargetUser
                                    AccessRights = @('ReadPermission')
                                    Confirm      = $false
                                }
                                $Results.Add("Removed $($TargetUser) from $($Username) Read Permissions")
                            }
                        }
                        'ExternalAccount' {
                            if ($Modification -eq 'Remove') {
                                $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Remove-MailboxPermission' -cmdParams @{
                                    Identity     = $UserId
                                    User         = $TargetUser
                                    AccessRights = @('ExternalAccount')
                                    Confirm      = $false
                                }
                                $Results.Add("Removed $($TargetUser) from $($Username) Read Permissions")
                            }
                        }
                        'DeleteItem' {
                            if ($Modification -eq 'Remove') {
                                $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Remove-MailboxPermission' -cmdParams @{
                                    Identity     = $UserId
                                    User         = $TargetUser
                                    AccessRights = @('DeleteItem')
                                    Confirm      = $false
                                }
                                $Results.Add("Removed $($TargetUser) from $($Username) Read Permissions")
                            }
                        }
                        'ChangePermission' {
                            if ($Modification -eq 'Remove') {
                                $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Remove-MailboxPermission' -cmdParams @{
                                    Identity     = $UserId
                                    User         = $TargetUser
                                    AccessRights = @('ChangePermission')
                                    Confirm      = $false
                                }
                                $Results.Add("Removed $($TargetUser) from $($Username) Read Permissions")
                            }
                        }
                        'ChangeOwner' {
                            if ($Modification -eq 'Remove') {
                                $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Remove-MailboxPermission' -cmdParams @{
                                    Identity     = $UserId
                                    User         = $TargetUser
                                    AccessRights = @('ChangeOwner')
                                    Confirm      = $false
                                }
                                $Results.Add("Removed $($TargetUser) from $($Username) Read Permissions")
                            }
                        }
                    }
                    Write-LogMessage -headers $Headers -API $APIName -message "Executed $($PermissionLevel) permission modification for $($TargetUser) on $($Username)" -Sev 'Info' -tenant $TenantFilter
                } catch {
                    Write-LogMessage -headers $Headers -API $APIName -message "Could not execute $($PermissionLevel) permission modification for $($TargetUser) on $($Username)" -Sev 'Error' -tenant $TenantFilter
                    $Results.Add("Could not execute $($PermissionLevel) permission modification for $($TargetUser) on $($Username). Error: $($_.Exception.Message)")
                }
            }
        }
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = @($Results) }
    }
}
