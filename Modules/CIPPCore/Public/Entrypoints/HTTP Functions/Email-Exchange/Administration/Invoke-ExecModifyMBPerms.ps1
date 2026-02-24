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
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Extract mailbox requests - handle all three formats
    $MailboxRequests = $null
    $Results = [System.Collections.ArrayList]::new()

    # Direct array format
    if ($request.body -is [array]) {
        $MailboxRequests = $request.body
    }
    # Bulk format with mailboxRequests property
    elseif ($request.body.mailboxRequests) {
        $MailboxRequests = $request.body.mailboxRequests
    }
    # Legacy single mailbox format
    elseif ($request.body.userID -and $request.body.permissions) {
        $MailboxRequests = @([PSCustomObject]@{
            userID = $request.body.userID
            tenantFilter = $request.body.tenantFilter
            permissions = $request.body.permissions
        })
    }

    if (-not $MailboxRequests -or $MailboxRequests.Count -eq 0) {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message 'No mailbox requests provided' -Sev 'Error'
        $body = [pscustomobject]@{'Results' = @("No mailbox requests provided") }
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = $Body
        })
        return
    }

    $TenantFilter = $Request.body.tenantFilter
    Write-LogMessage -headers $Request.Headers -API $APINAME -message "Processing permission changes for $($MailboxRequests.Count) mailboxes" -Sev 'Info' -tenant $TenantFilter

    # Build cmdlet array for processing
    $CmdletArray = [System.Collections.ArrayList]::new()
    $CmdletMetadataArray = [System.Collections.ArrayList]::new()
    $GuidToMetadataMap = @{}  # Map GUIDs to our metadata
    $UserLookupCache = @{}

    foreach ($MailboxRequest in $MailboxRequests) {
        $Username = $MailboxRequest.userID
        $Permissions = $MailboxRequest.permissions

        if ([string]::IsNullOrEmpty($Username)) {
            $null = $Results.Add("Skipped mailbox with missing userID")
            continue
        }

        # User lookup with caching for bulk operations
        if (-not $UserLookupCache.ContainsKey($Username)) {
            try {
                $UserObject = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)" -tenantid $TenantFilter
                $UserLookupCache[$Username] = $UserObject.userPrincipalName
            }
            catch {
                try {
                    $UserObject = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=userPrincipalName eq '$Username'" -tenantid $TenantFilter
                    if ($UserObject.value -and $UserObject.value.Count -gt 0) {
                        $UserLookupCache[$Username] = $UserObject.value[0].userPrincipalName
                    } else {
                        throw "User not found"
                    }
                }
                catch {
                    Write-LogMessage -headers $Request.Headers -API $APINAME -message "Could not find user $($Username)" -Sev 'Error' -tenant $TenantFilter
                    $null = $Results.Add("Could not find user $($Username)")
                    continue
                }
            }
        }
        $UserId = $UserLookupCache[$Username]

        # Convert permissions to array if needed
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

            # Handle multiple permission levels
            $PermissionLevelArray = if ($PermissionLevels -like "*,*") {
                $PermissionLevels -split ',' | ForEach-Object { $_.Trim() }
            } else {
                @($PermissionLevels.Trim())
            }

            # Extract target users from UserID (handle array of objects or single values)
            $TargetUsers = if ($Permission.UserID -is [array]) {
                $Permission.UserID | ForEach-Object {
                    if ($_ -is [PSCustomObject] -and $_.value) {
                        $_.value
                    } else {
                        $_.ToString()
                    }
                }
            } else {
                if ($Permission.UserID -is [PSCustomObject] -and $Permission.UserID.value) {
                    @($Permission.UserID.value)
                } else {
                    @($Permission.UserID.ToString())
                }
            }

            foreach ($TargetUser in $TargetUsers) {
                foreach ($PermissionLevel in $PermissionLevelArray) {

                    # Create cmdlet parameters based on permission type and action
                    $CmdletParams = @{}
                    $CmdletName = ""
                    $ExpectedResult = ""

                    switch ($PermissionLevel) {
                        'FullAccess' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('FullAccess')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Removed $($TargetUser) from $($Username) FullAccess permissions"
                            } else {
                                $CmdletName = 'Add-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('FullAccess')
                                    automapping  = $AutoMap
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Granted $($TargetUser) FullAccess to $($Username) with automapping $($AutoMap)"
                            }
                        }
                        'SendAs' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-RecipientPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    Trustee      = $TargetUser
                                    accessRights = @('SendAs')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Removed $($TargetUser) SendAs permissions from $($Username)"
                            } else {
                                $CmdletName = 'Add-RecipientPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    Trustee      = $TargetUser
                                    accessRights = @('SendAs')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Granted $($TargetUser) SendAs permissions to $($Username)"
                            }
                        }
                        'SendOnBehalf' {
                            $CmdletName = 'Set-Mailbox'
                            if ($Modification -eq 'Remove') {
                                $CmdletParams = @{
                                    Identity            = $UserId
                                    GrantSendonBehalfTo = @{
                                        '@odata.type' = '#Exchange.GenericHashTable'
                                        remove        = $TargetUser
                                    }
                                    Confirm             = $false
                                }
                                $ExpectedResult = "Removed $($TargetUser) SendOnBehalf permissions from $($Username)"
                            } else {
                                $CmdletParams = @{
                                    Identity            = $UserId
                                    GrantSendonBehalfTo = @{
                                        '@odata.type' = '#Exchange.GenericHashTable'
                                        add           = $TargetUser
                                    }
                                    Confirm             = $false
                                }
                                $ExpectedResult = "Granted $($TargetUser) SendOnBehalf permissions to $($Username)"
                            }
                        }
                        'ReadPermission' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('ReadPermission')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Removed $($TargetUser) ReadPermission from $($Username)"
                            }
                        }
                        'ExternalAccount' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('ExternalAccount')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Removed $($TargetUser) ExternalAccount permissions from $($Username)"
                            }
                        }
                        'DeleteItem' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('DeleteItem')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Removed $($TargetUser) DeleteItem permissions from $($Username)"
                            }
                        }
                        'ChangePermission' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('ChangePermission')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Removed $($TargetUser) ChangePermission from $($Username)"
                            }
                        }
                        'ChangeOwner' {
                            if ($Modification -eq 'Remove') {
                                $CmdletName = 'Remove-MailboxPermission'
                                $CmdletParams = @{
                                    Identity     = $UserId
                                    user         = $TargetUser
                                    accessRights = @('ChangeOwner')
                                    Confirm      = $false
                                }
                                $ExpectedResult = "Removed $($TargetUser) ChangeOwner permissions from $($Username)"
                            }
                        }
                    }

                    if ($CmdletName) {
                        # Generate unique GUID for this operation
                        $OperationGuid = [Guid]::NewGuid().ToString()

                        $CmdletObj = @{
                            CmdletInput = @{
                                CmdletName = $CmdletName
                                Parameters = $CmdletParams
                            }
                            OperationGuid = $OperationGuid  # Add GUID to cmdlet object
                        }

                        $CmdletMetadata = [PSCustomObject]@{
                            ExpectedResult = $ExpectedResult
                            Mailbox = $Username
                            TargetUser = $TargetUser
                            Permission = $PermissionLevel
                            Action = $Modification
                            OperationGuid = $OperationGuid
                        }

                        $null = $CmdletArray.Add($CmdletObj)
                        $null = $CmdletMetadataArray.Add($CmdletMetadata)

                        # Map GUID to metadata for precise result mapping
                        $GuidToMetadataMap[$OperationGuid] = $CmdletMetadata
                    }
                }
            }
        }
    }

    if ($CmdletArray.Count -eq 0) {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message 'No valid cmdlets to process' -sev 'Warn' -tenant $TenantFilter
        $body = [pscustomobject]@{'Results' = @("No valid permission changes to process") }
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
        return
    }

    # Execute requests - use enhanced bulk processing with GUID mapping
    if ($CmdletArray.Count -gt 1) {
        # Use bulk processing with GUID tracking
        try {
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Executing bulk request with $($CmdletArray.Count) cmdlets" -Sev 'Info' -tenant $TenantFilter
            $BulkResults = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($CmdletArray) -ReturnWithCommand $true

            # Process bulk results using GUID mapping
            if ($BulkResults -is [hashtable] -and $BulkResults.Keys.Count -gt 0) {
                foreach ($cmdletName in $BulkResults.Keys) {
                    foreach ($result in $BulkResults[$cmdletName]) {
                        $operationGuid = $result.OperationGuid

                        if ($operationGuid -and $GuidToMetadataMap.ContainsKey($operationGuid)) {
                            $metadata = $GuidToMetadataMap[$operationGuid]

                            if ($result.error) {
                                $ErrorMessage = try { (Get-CippException -Exception $result.error).NormalizedError } catch { $result.error }
                                $null = $Results.Add("Error processing $($metadata.Permission) for $($metadata.TargetUser) on $($metadata.Mailbox): $ErrorMessage")
                                Write-LogMessage -headers $Request.Headers -API $APINAME -message "Error for operation $operationGuid`: $ErrorMessage" -Sev 'Error' -tenant $TenantFilter
                            } else {
                                $null = $Results.Add($metadata.ExpectedResult)
                                Write-LogMessage -headers $Request.Headers -API $APINAME -message "Success for operation $operationGuid`: $($metadata.ExpectedResult)" -Sev 'Info' -tenant $TenantFilter
                            }
                        } else {
                            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Could not map result to operation. GUID: $operationGuid, Available GUIDs: $($GuidToMetadataMap.Keys -join ', ')" -sev 'Warn' -tenant $TenantFilter

                            # Fallback for unmapped results
                            if ($result.error) {
                                $ErrorMessage = try { (Get-CippException -Exception $result.error).NormalizedError } catch { $result.error }
                                $null = $Results.Add("Error in $cmdletName`: $ErrorMessage")
                            } else {
                                $null = $Results.Add("Completed $cmdletName operation")
                            }
                        }
                    }
                }
            } else {
                # If no results returned but no error thrown, assume all succeeded
                foreach ($CmdletMetadata in $CmdletMetadataArray) {
                    if ($CmdletMetadata.ExpectedResult) {
                        $null = $Results.Add($CmdletMetadata.ExpectedResult)
                    }
                }
            }

            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Bulk request completed successfully" -Sev 'Info' -tenant $TenantFilter
        }
        catch {
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Bulk request failed, using fallback: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter

            # Fallback to individual processing
            for ($i = 0; $i -lt $CmdletArray.Count; $i++) {
                $CmdletObj = $CmdletArray[$i]
                $CmdletMetadata = $CmdletMetadataArray[$i]
                try {
                    $null = New-ExoRequest -Anchor $CmdletMetadata.Mailbox -tenantid $TenantFilter -cmdlet $CmdletObj.CmdletInput.CmdletName -cmdParams $CmdletObj.CmdletInput.Parameters
                    $null = $Results.Add($CmdletMetadata.ExpectedResult)
                }
                catch {
                    $null = $Results.Add("Error processing $($CmdletMetadata.Permission) for $($CmdletMetadata.TargetUser) on $($CmdletMetadata.Mailbox): $($_.Exception.Message)")
                }
            }
        }
    }
    else {
        # Use individual processing for single operation
        $CmdletObj = $CmdletArray[0]
        $CmdletMetadata = $CmdletMetadataArray[0]
        try {
            $null = New-ExoRequest -Anchor $CmdletMetadata.Mailbox -tenantid $TenantFilter -cmdlet $CmdletObj.CmdletInput.CmdletName -cmdParams $CmdletObj.CmdletInput.Parameters
            $null = $Results.Add($CmdletMetadata.ExpectedResult)
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Executed $($CmdletMetadata.Permission) permission modification" -Sev 'Info' -tenant $TenantFilter
        }
        catch {
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Permission modification failed: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
            $null = $Results.Add("Error processing $($CmdletMetadata.Permission) for $($CmdletMetadata.TargetUser) on $($CmdletMetadata.Mailbox): $($_.Exception.Message)")
        }
    }

    $body = [pscustomobject]@{'Results' = @($Results) }
    return ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
}
