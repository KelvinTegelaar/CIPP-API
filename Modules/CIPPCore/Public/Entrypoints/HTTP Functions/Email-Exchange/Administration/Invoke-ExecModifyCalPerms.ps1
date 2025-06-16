using namespace System.Net

Function Invoke-ExecModifyCalPerms {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Calendar.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME-message 'Accessed this API' -Sev 'Debug'
    
    $Username = $request.body.userID
    $Tenantfilter = $request.body.tenantfilter
    $Permissions = $request.body.permissions

    Write-LogMessage -headers $Request.Headers -API $APINAME-message "Processing request for user: $Username, tenant: $Tenantfilter" -Sev 'Debug'

    if ($username -eq $null) { 
        Write-LogMessage -headers $Request.Headers -API $APINAME-message 'Username is null' -Sev 'Error'
        $body = [pscustomobject]@{'Results' = @('Username is required') }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $Body
            })
        return
    }
    
    try {
        $userid = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($username)" -tenantid $Tenantfilter).id
        Write-LogMessage -headers $Request.Headers -API $APINAME-message "Retrieved user ID: $userid" -Sev 'Debug'
    }
    catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME-message "Failed to get user ID: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = @("Failed to get user ID: $($_.Exception.Message)") }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body       = $Body
            })
        return
    }

    $Results = [System.Collections.ArrayList]::new()
    $HasErrors = $false

    # Convert permissions to array format if it's an object with numeric keys
    if ($Permissions -is [PSCustomObject]) {
        if ($Permissions.PSObject.Properties.Name -match '^\d+$') {
            $Permissions = $Permissions.PSObject.Properties.Value
        }
        else {
            $Permissions = @($Permissions)
        }
    }

    Write-LogMessage -headers $Request.Headers -API $APINAME-message "Processing $($Permissions.Count) permission entries" -Sev 'Debug'

    foreach ($Permission in $Permissions) {
        Write-LogMessage -headers $Request.Headers -API $APINAME-message "Processing permission: $($Permission | ConvertTo-Json)" -Sev 'Debug'
        
        $PermissionLevel = $Permission.PermissionLevel.value ?? $Permission.PermissionLevel
        $Modification = $Permission.Modification
        $CanViewPrivateItems = $Permission.CanViewPrivateItems ?? $false
        
        Write-LogMessage -headers $Request.Headers -API $APINAME-message "Permission Level: $PermissionLevel, Modification: $Modification, CanViewPrivateItems: $CanViewPrivateItems" -Sev 'Debug'
        
        # Handle UserID as array or single value
        $TargetUsers = @($Permission.UserID | ForEach-Object { $_.value ?? $_ })

        Write-LogMessage -headers $Request.Headers -API $APINAME-message "Target Users: $($TargetUsers -join ', ')" -Sev 'Debug'

        foreach ($TargetUser in $TargetUsers) {
            try {
                Write-LogMessage -headers $Request.Headers -API $APINAME-message "Processing target user: $TargetUser" -Sev 'Debug'
                
                if ($Modification -eq 'Remove') {
                    try {
                        $CalPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Remove-MailboxFolderPermission' -cmdParams @{
                            Identity = "$($userid):\Calendar"
                            User     = $TargetUser
                            Confirm  = $false
                        }
                        $null = $results.Add("Removed $($TargetUser) from $($username) Calendar permissions")
                    }
                    catch {
                        $null = $results.Add("No existing permissions to remove for $($TargetUser)")
                    }
                }
                else {
                    Write-LogMessage -headers $Request.Headers -API $APINAME-message "Setting permissions with AccessRights: $PermissionLevel" -Sev 'Debug'

                    $cmdParams = @{
                        Identity     = "$($userid):\Calendar"
                        User         = $TargetUser
                        AccessRights = $PermissionLevel
                        Confirm      = $false
                    }

                    if ($CanViewPrivateItems) {
                        $cmdParams['SharingPermissionFlags'] = 'Delegate,CanViewPrivateItems'
                    }

                    try {
                        # Try Add first
                        $CalPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Add-MailboxFolderPermission' -cmdParams $cmdParams
                        $null = $results.Add("Granted $($TargetUser) $($PermissionLevel) access to $($username) Calendar$($CanViewPrivateItems ? ' with access to private items' : '')")
                    }
                    catch {
                        # If Add fails, try Set
                        $CalPerms = New-ExoRequest -Anchor $username -tenantid $Tenantfilter -cmdlet 'Set-MailboxFolderPermission' -cmdParams $cmdParams
                        $null = $results.Add("Updated $($TargetUser) $($PermissionLevel) access to $($username) Calendar$($CanViewPrivateItems ? ' with access to private items' : '')")
                    }
                }
                Write-LogMessage -headers $Request.Headers -API $APINAME-message "Successfully executed $($PermissionLevel) permission modification for $($TargetUser) on $($username)" -Sev 'Info' -tenant $TenantFilter
            }
            catch {
                $HasErrors = $true
                Write-LogMessage -headers $Request.Headers -API $APINAME-message "Could not execute $($PermissionLevel) permission modification for $($TargetUser) on $($username). Error: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
                $null = $results.Add("Could not execute $($PermissionLevel) permission modification for $($TargetUser) on $($username). Error: $($_.Exception.Message)")
            }
        }
    }

    if ($results.Count -eq 0) {
        Write-LogMessage -headers $Request.Headers -API $APINAME-message 'No results were generated from the operation' -Sev 'Warning'
        $null = $results.Add('No results were generated from the operation. Please check the logs for more details.')
        $HasErrors = $true
    }

    $body = [pscustomobject]@{'Results' = @($results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = if ($HasErrors) { [HttpStatusCode]::InternalServerError } else { [HttpStatusCode]::OK }
            Body       = $Body
        })
} 