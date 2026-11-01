function Invoke-ExecModifyCalPerms {
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

    $TenantFilter = $Request.Body.tenantFilter

    # Bulk format: { tenantFilter, mailboxRequests: [{ userID, permissions }] }; legacy: { tenantFilter, userID, permissions }
    $IsBulk = [bool]$Request.Body.mailboxRequests
    $MailboxRequests = if ($IsBulk) {
        @($Request.Body.mailboxRequests)
    } else {
        @([PSCustomObject]@{ userID = $Request.Body.userID; permissions = $Request.Body.permissions })
    }

    $Results = [System.Collections.Generic.List[string]]::new()
    $HasErrors = $false
    $Failed = 0
    # One cache context per request: the cache sync reads the tenant's cached mailboxes and calendar rows once
    $CacheContext = @{}

    foreach ($MailboxRequest in $MailboxRequests) {
        # UPN of the mailbox to modify calendar permissions for
        $Username = $MailboxRequest.userID
        $Permissions = $MailboxRequest.permissions

        Write-LogMessage -headers $Headers -API $APIName -message "Processing request for user: $Username, tenant: $TenantFilter" -Sev 'Debug'

        if ([string]::IsNullOrWhiteSpace($Username)) {
            Write-LogMessage -headers $Headers -API $APIName -message 'Username is null or whitespace' -Sev 'Error'
            if ($IsBulk) {
                $Failed++
                $Results.Add('Username is required')
                continue
            }
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{'Results' = @('Username is required') }
                })
        }

        try {
            try {
                $UserId = [guid]$Username
            } catch {
                # If not a GUID, assume it's a UPN and look up the ID via Graph
                $UserId = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)" -tenantid $TenantFilter).id
                Write-LogMessage -headers $Headers -API $APIName -message "Retrieved user ID: $UserId" -Sev 'Debug'
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $Headers -API $APIName -message "Failed to get user ID: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            if ($IsBulk) {
                # One unresolvable mailbox must not abort the rest of the batch
                $Failed++
                $Results.Add("Failed to get user ID for $($Username): $($ErrorMessage.NormalizedError)")
                continue
            }
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{'Results' = @("Failed to get user ID: $($ErrorMessage.NormalizedError)") }
                })
        }

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
            $SendNotificationToUser = $Permission.SendNotificationToUser ?? $false

            Write-LogMessage -headers $Headers -API $APIName -message "Permission Level: $PermissionLevel, Modification: $Modification, CanViewPrivateItems: $CanViewPrivateItems, FolderName: $FolderName" -Sev 'Debug'

            # Handle UserID as array or single value
            $TargetUsers = @($Permission.UserID | ForEach-Object { $_.value ?? $_ })

            Write-LogMessage -headers $Headers -API $APIName -message "Target Users: $($TargetUsers -join ', ')" -Sev 'Debug'

            foreach ($TargetUser in $TargetUsers) {
                try {
                    Write-LogMessage -headers $Headers -API $APIName -message "Processing target user: $TargetUser" -Sev 'Debug'
                    $Params = @{
                        APIName                = $APIName
                        Headers                = $Headers
                        RemoveAccess           = if ($Modification -eq 'Remove') { $TargetUser } else { $null }
                        TenantFilter           = $TenantFilter
                        UserID                 = $UserId
                        folderName             = $FolderName
                        UserToGetPermissions   = $TargetUser
                        # TargetUser may be a recipient id, so log the display name the caller saw
                        LoggingName            = $Permission.DisplayName ?? $TargetUser
                        Permissions            = $PermissionLevel
                        CanViewPrivateItems    = $CanViewPrivateItems
                        SendNotificationToUser = $SendNotificationToUser
                        CacheContext           = $CacheContext
                    }

                    # Write-Host "Request params: $($Params | ConvertTo-Json)"
                    $Result = Set-CIPPCalendarPermission @Params

                    $Results.Add($Result)
                } catch {
                    $Failed++
                    $Results.Add("$($_.Exception.Message)")
                }
            }
        }
    }

    if ($Results.Count -eq 0) {
        Write-LogMessage -headers $Headers -API $APIName -message 'No results were generated from the operation' -sev 'Warning'
        $Results.Add('No results were generated from the operation. Please check the logs for more details.')
        $HasErrors = $true
    }

    return ([HttpResponseContext]@{
            StatusCode = if ($HasErrors) { [HttpStatusCode]::InternalServerError } else { Get-CippBulkStatusCode -Total $Results.Count -Failed $Failed }
            Body       = @{'Results' = @($Results) }
        })
}
