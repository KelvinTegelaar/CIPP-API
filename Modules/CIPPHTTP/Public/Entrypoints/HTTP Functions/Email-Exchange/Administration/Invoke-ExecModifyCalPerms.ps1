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

    if (-not $IsBulk -and [string]::IsNullOrWhiteSpace($Request.Body.userID)) {
        Write-LogMessage -headers $Headers -API $APIName -message 'Username is null or whitespace' -Sev 'Error'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{'Results' = @('Username is required') }
            })
    }

    $Results = [System.Collections.Generic.List[string]]::new()
    $Failed = 0
    # One cache context per request: the cache sync reads the tenant's cached mailboxes and calendar rows once
    $CacheContext = @{}

    # Mailboxes arrive as object ids or UPNs; resolve the UPNs in one Graph batch
    $Upns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($MailboxRequest in $MailboxRequests) {
        $Username = [string]$MailboxRequest.userID
        if ($Username -and -not ($Username -as [guid])) { $null = $Upns.Add($Username) }
    }
    $IdByUpn = @{}
    $LookupError = 'not found'
    if ($Upns.Count -gt 0) {
        $UpnList = @($Upns)
        try {
            $Lookups = New-GraphBulkRequest -tenantid $TenantFilter -Requests @(
                for ($i = 0; $i -lt $UpnList.Count; $i++) { @{ id = "$i"; method = 'GET'; url = "users/$($UpnList[$i])?`$select=id" } })
            foreach ($Lookup in $Lookups) { if ($Lookup.body.id) { $IdByUpn[$UpnList[[int]$Lookup.id]] = $Lookup.body.id } }
        } catch {
            $LookupError = (Get-CippException -Exception $_).NormalizedError
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to look up mailboxes: $LookupError" -Sev 'Error'
        }
    }

    $Ops = [System.Collections.Generic.List[object]]::new()
    foreach ($MailboxRequest in $MailboxRequests) {
        # UPN or object id of the mailbox to modify calendar permissions for
        $Username = [string]$MailboxRequest.userID
        if ([string]::IsNullOrWhiteSpace($Username)) {
            $Failed++
            $Results.Add('Username is required')
            continue
        }
        $MailboxId = if ($Username -as [guid]) { $Username } else { $IdByUpn[$Username] }
        if (-not $MailboxId) {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to get user ID for $($Username): $LookupError" -Sev 'Error'
            if (-not $IsBulk) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body       = @{'Results' = @("Failed to get user ID: $LookupError") }
                    })
            }
            # One unresolvable mailbox must not abort the rest of the batch
            $Failed++
            $Results.Add("Failed to get user ID for $($Username): $LookupError")
            continue
        }

        # Convert permissions to array format if it's an object with numeric keys
        $Permissions = $MailboxRequest.permissions
        if ($Permissions -is [PSCustomObject] -and $Permissions.PSObject.Properties.Name -match '^\d+$') {
            $Permissions = $Permissions.PSObject.Properties.Value
        }

        foreach ($Permission in @($Permissions)) {
            foreach ($Target in @($Permission.UserID)) {
                $TargetUser = $Target.value ?? $Target
                $Ops.Add([PSCustomObject]@{
                        MailboxId           = $MailboxId
                        Mailbox             = $Username
                        User                = $TargetUser
                        # TargetUser may be a recipient id, so log the display name the caller saw
                        LoggingName         = $Permission.DisplayName ?? $TargetUser
                        Level               = $Permission.PermissionLevel.value ?? $Permission.PermissionLevel
                        Remove              = $Permission.Modification -eq 'Remove'
                        FolderName          = $Permission.FolderName
                        CanViewPrivateItems = [bool]$Permission.CanViewPrivateItems
                        Notify              = [bool]$Permission.SendNotificationToUser
                        FolderIdentity      = $null
                        Done                = $false
                        Error               = $null
                    })
            }
        }
    }

    # Bulk adds send no FolderName: the calendar's localized name differs per mailbox, so look up its id
    $FolderById = @{}
    $NeedFolder = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($Op in $Ops) { if (-not $Op.FolderName) { $null = $NeedFolder.Add($Op.MailboxId) } }
    if ($NeedFolder.Count -gt 0) {
        try {
            $Stats = New-ExoBulkRequest -tenantid $TenantFilter -AnchorPerMailbox -MaxConcurrency 32 -ReturnWithCommand $true -cmdletArray @(
                foreach ($Id in $NeedFolder) { @{ CmdletInput = @{ CmdletName = 'Get-MailboxFolderStatistics'; Parameters = @{ Identity = $Id; FolderScope = 'Calendar' } }; OperationGuid = $Id } })
            foreach ($Stat in @($Stats['Get-MailboxFolderStatistics'])) {
                # FolderType is an internal enum, always English regardless of mailbox language
                if ($Stat.FolderType -eq 'Calendar') { $FolderById[$Stat.OperationGuid] = $Stat }
            }
        } catch {
            # Unresolved mailboxes use the English folder name, which works for English mailboxes
            Write-Information "Calendar folder lookup failed: $($_.Exception.Message)"
        }
    }
    foreach ($Op in $Ops) {
        $Folder = $FolderById[$Op.MailboxId]
        if ($Op.FolderName -or -not $Folder) {
            if (-not $Op.FolderName) { $Op.FolderName = 'Calendar' }
            $Op.FolderIdentity = "$($Op.MailboxId):\$($Op.FolderName)"
        } else {
            $Op.FolderName = $Folder.Name
            $Op.FolderIdentity = "$($Op.MailboxId):$($Folder.FolderId)"
        }
    }

    # Add first; entries that already exist are updated with Set in a second pass. New-ExoBulkRequest
    # runs each mailbox's changes in order and different mailboxes concurrently.
    $Pending = @(for ($i = 0; $i -lt $Ops.Count; $i++) { @{ Index = $i; CmdletName = if ($Ops[$i].Remove) { 'Remove-MailboxFolderPermission' } else { 'Add-MailboxFolderPermission' } } })
    $Ambiguous = [System.Collections.Generic.List[object]]::new()
    while ($Pending.Count -gt 0) {
        $Requests = foreach ($Item in $Pending) {
            $Op = $Ops[$Item.Index]
            $Params = @{ Identity = $Op.FolderIdentity; User = $Op.User }
            if (-not $Op.Remove) {
                $Params.AccessRights = @($Op.Level)
                $Params.SendNotificationToUser = $Op.Notify
                if ($Op.CanViewPrivateItems) { $Params.SharingPermissionFlags = 'Delegate,CanViewPrivateItems' }
            }
            @{ CmdletInput = @{ CmdletName = $Item.CmdletName; Parameters = $Params }; OperationGuid = "$($Item.Index)" }
        }
        $Retry = [System.Collections.Generic.List[object]]::new()
        try {
            $Responses = New-ExoBulkRequest -tenantid $TenantFilter -AnchorPerMailbox -MaxConcurrency 32 -ReturnWithCommand $true -cmdletArray @($Requests)
        } catch {
            $ErrorMessage = (Get-CippException -Exception $_).NormalizedError
            foreach ($Item in $Pending) { $Ops[$Item.Index].Error = $ErrorMessage }
            break
        }
        foreach ($CmdletName in $Responses.Keys) {
            foreach ($Response in @($Responses[$CmdletName])) {
                $Op = $Ops[[int]$Response.OperationGuid]
                if (-not $Response.error) {
                    $Op.Done = $true
                } elseif ($CmdletName -eq 'Add-MailboxFolderPermission' -and "$($Response.error)" -match 'UserAlreadyExistsInPermissionEntryException') {
                    $Retry.Add(@{ Index = [int]$Response.OperationGuid; CmdletName = 'Set-MailboxFolderPermission' })
                } elseif ($CmdletName -eq 'Remove-MailboxFolderPermission' -and "$($Response.error)" -match 'ManagementObjectAmbiguousException') {
                    $Ambiguous.Add($Op)
                } else {
                    $Op.Error = Get-NormalizedError -Message "$($Response.error)"
                }
            }
        }
        $Pending = $Retry
    }

    # Two recipients share the grantee's display name: resolve which one holds the entry
    foreach ($Op in $Ambiguous) {
        try {
            $null = Remove-CIPPFolderPermission -TenantFilter $TenantFilter -FolderIdentity $Op.FolderIdentity -User $Op.User -AccessRights ($Op.Level -join ', ') -Anchor $Op.MailboxId
            $Op.Done = $true
        } catch {
            $Op.Error = $_.Exception.Message
        }
    }

    foreach ($Op in $Ops) {
        if (-not $Op.Done) {
            $Failed++
            $Message = "Failed to set calendar permissions for $($Op.LoggingName) on $($Op.Mailbox) : $($Op.Error ?? 'Exchange returned no result')"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error'
            $Results.Add($Message)
            continue
        }
        if ($Op.Remove) {
            $Message = "Successfully removed access for $($Op.LoggingName) from calendar $($Op.FolderIdentity)"
        } else {
            $Message = "Successfully set permissions on folder $($Op.FolderIdentity). The user $($Op.LoggingName) now has $($Op.Level) permissions on this folder."
            if ($Op.CanViewPrivateItems) { $Message += ' The user can also view private items.' }
            if ($Op.Notify) { $Message += ' A notification has been sent to the user.' }
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        $Results.Add($Message)
        try {
            Sync-CIPPCalendarPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $Op.MailboxId -FolderName $Op.FolderName -User $Op.User -Permissions $Op.Level -Action ($Op.Remove ? 'Remove' : 'Add') -CacheContext $CacheContext
        } catch {
            Write-Information "Cache sync warning: $($_.Exception.Message)"
        }
    }

    if ($Results.Count -eq 0) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{'Results' = @('No calendar permission changes were requested') }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = Get-CippBulkStatusCode -Total $Results.Count -Failed $Failed
            Body       = @{'Results' = @($Results) }
        })
}
