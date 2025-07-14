using namespace System.Net

Function Invoke-ExecModifyCalPerms {
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

    Write-LogMessage -headers $Headers -API $APIName -message "Processing request for user: $Username, tenant: $TenantFilter" -Sev 'Debug'

    if ($null -eq $Username) {
        Write-LogMessage -headers $Headers -API $APIName -message 'Username is null' -Sev 'Error'
        $body = [pscustomobject]@{'Results' = @('Username is required') }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $Body
            })
        return
    }

    try {
        $UserId = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)" -tenantid $TenantFilter).id
        Write-LogMessage -headers $Headers -API $APIName -message "Retrieved user ID: $UserId" -Sev 'Debug'
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to get user ID: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = @("Failed to get user ID: $($_.Exception.Message)") }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body       = $Body
            })
        return
    }

    $Results = [System.Collections.Generic.List[string]]::new()
    $HasErrors = $false

    # Convert permissions to array format if it's an object with numeric keys
    if ($Permissions -is [PSCustomObject]) {
        if ($Permissions.PSObject.Properties.Name -match '^\d+$') {
            $Permissions = $Permissions.PSObject.Properties.Value
        } else {
            $Permissions = @($Permissions)
        }
    }

    Write-LogMessage -headers $Headers -API $APIName -message "Processing $($Permissions.Count) permission entries" -Sev 'Debug'

    foreach ($Permission in $Permissions) {
        Write-LogMessage -headers $Headers -API $APIName -message "Processing permission: $($Permission | ConvertTo-Json)" -Sev 'Debug'

        $PermissionLevel = $Permission.PermissionLevel.value ?? $Permission.PermissionLevel
        $Modification = $Permission.Modification
        $CanViewPrivateItems = $Permission.CanViewPrivateItems ?? $false
        $FolderName = $Permission.FolderName ?? 'Calendar'

        Write-LogMessage -headers $Headers -API $APIName -message "Permission Level: $PermissionLevel, Modification: $Modification, CanViewPrivateItems: $CanViewPrivateItems, FolderName: $FolderName" -Sev 'Debug'

        # Handle UserID as array or single value
        $TargetUsers = @($Permission.UserID | ForEach-Object { $_.value ?? $_ })

        Write-LogMessage -headers $Headers -API $APIName -message "Target Users: $($TargetUsers -join ', ')" -Sev 'Debug'

        foreach ($TargetUser in $TargetUsers) {
            try {
                Write-LogMessage -headers $Headers -API $APIName -message "Processing target user: $TargetUser" -Sev 'Debug'
                $Params = @{
                    APIName              = $APIName
                    Headers              = $Headers
                    RemoveAccess         = if ($Modification -eq 'Remove') { $TargetUser } else { $null }
                    TenantFilter         = $TenantFilter
                    UserID               = $UserId
                    folderName           = $FolderName
                    UserToGetPermissions = $TargetUser
                    LoggingName          = $TargetUser
                    Permissions          = $PermissionLevel
                    CanViewPrivateItems  = $CanViewPrivateItems
                }

                # Write-Host "Request params: $($Params | ConvertTo-Json)"
                $Result = Set-CIPPCalendarPermission @Params

                $null = $Results.Add($Result)
            } catch {
                $HasErrors = $true
                $null = $Results.Add("$($_.Exception.Message)")
            }
        }
    }

    if ($Results.Count -eq 0) {
        Write-LogMessage -headers $Headers -API $APIName -message 'No results were generated from the operation' -Sev 'Warning'
        $null = $Results.Add('No results were generated from the operation. Please check the logs for more details.')
        $HasErrors = $true
    }

    $Body = [pscustomobject]@{'Results' = @($Results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = if ($HasErrors) { [HttpStatusCode]::InternalServerError } else { [HttpStatusCode]::OK }
            Body       = $Body
        })
}
