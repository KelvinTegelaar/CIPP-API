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

    # Extract mailbox requests - handle all three formats
    $MailboxRequests = $null
    $Results = [System.Collections.ArrayList]::new()
    $SuccessfulOps = [System.Collections.ArrayList]::new()

    # Direct array format
    if ($Request.Body -is [array]) {
        $MailboxRequests = $Request.Body
    }
    # Bulk format with mailboxRequests property
    elseif ($Request.Body.mailboxRequests) {
        $MailboxRequests = $Request.Body.mailboxRequests
    }
    # Legacy single mailbox format
    elseif ($Request.Body.userID -and $Request.Body.permissions) {
        $MailboxRequests = @([PSCustomObject]@{
                userID       = $Request.Body.userID
                tenantFilter = $Request.Body.tenantFilter
                permissions  = $Request.Body.permissions
            })
    }

    if (-not $MailboxRequests -or $MailboxRequests.Count -eq 0) {
        Write-LogMessage -headers $Headers -API $APIName -message 'No mailbox requests provided' -Sev 'Error'
        $body = [pscustomobject]@{'Results' = @('No mailbox requests provided') }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $Body
            })
        return
    }

    $TenantFilter = $Request.Body.tenantFilter
    Write-LogMessage -headers $Headers -API $APIName -message "Processing permission changes for $($MailboxRequests.Count) mailboxes" -Sev 'Info' -tenant $TenantFilter

    # Build cmdlet array for processing
    $CmdletArray = [System.Collections.ArrayList]::new()
    $CmdletMetadataArray = [System.Collections.ArrayList]::new()
    $GuidToMetadataMap = @{}  # Map GUIDs to our metadata
    $UserLookupCache = @{}

    # Permission levels Set-CIPPMailboxPermission understands (its ValidateSet). Levels outside this
    # set are silently skipped, matching the behaviour of the inline switch this used to carry.
    $SupportedPermissionLevels = @('FullAccess', 'SendAs', 'SendOnBehalf', 'ReadPermission', 'ExternalAccount', 'DeleteItem', 'ChangePermission', 'ChangeOwner')

    foreach ($MailboxRequest in $MailboxRequests) {
        $Username = $MailboxRequest.userID
        $Permissions = $MailboxRequest.permissions

        if ([string]::IsNullOrEmpty($Username)) {
            $null = $Results.Add('Skipped mailbox with missing userID')
            continue
        }

        # User lookup with caching for bulk operations
        if (-not $UserLookupCache.ContainsKey($Username)) {
            try {
                $UserObject = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)" -tenantid $TenantFilter
                $UserLookupCache[$Username] = $UserObject.userPrincipalName
            } catch {
                try {
                    $UserObject = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=userPrincipalName eq '$Username'" -tenantid $TenantFilter
                    if ($UserObject.value -and $UserObject.value.Count -gt 0) {
                        $UserLookupCache[$Username] = $UserObject.value[0].userPrincipalName
                    } else {
                        throw 'User not found'
                    }
                } catch {
                    Write-LogMessage -headers $Headers -API $APIName -message "Could not find user $($Username)" -Sev 'Error' -tenant $TenantFilter
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
            $PermissionLevelArray = if ($PermissionLevels -like '*,*') {
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

                    # Build the EXO cmdlet for this change via Set-CIPPMailboxPermission's
                    # -AsCmdletObject mode - the single source of truth for the permission-level ->
                    # cmdlet/parameter mapping. It returns @{ CmdletName; Parameters; ExpectedResult }
                    # for supported combinations, or a plain string for unsupported ones (e.g. an Add
                    # on a remove-only level), which we skip. The bulk machinery below is unchanged.
                    if ($PermissionLevel -notin $SupportedPermissionLevels) { continue }
                    $Action = if ($Modification -eq 'Remove') { 'Remove' } else { 'Add' }

                    $Mapping = Set-CIPPMailboxPermission -UserId $UserId -AccessUser $TargetUser -PermissionLevel $PermissionLevel -Action $Action -AutoMap $AutoMap -TenantFilter $TenantFilter -AsCmdletObject

                    if ($Mapping -is [hashtable] -and $Mapping.CmdletName) {
                        # Generate unique GUID for this operation
                        $OperationGuid = [Guid]::NewGuid().ToString()

                        $CmdletObj = @{
                            CmdletInput   = @{
                                CmdletName = $Mapping.CmdletName
                                Parameters = $Mapping.Parameters
                            }
                            OperationGuid = $OperationGuid  # Add GUID to cmdlet object
                        }

                        # Use the resolved UPN, not the raw request identifier (which may be an
                        # object id) - the cache sync below matches cached rows by mailbox UPN.
                        $CmdletMetadata = [PSCustomObject]@{
                            ExpectedResult = $Mapping.ExpectedResult
                            Mailbox        = $UserId
                            TargetUser     = $TargetUser
                            Permission     = $PermissionLevel
                            Action         = $Action
                            OperationGuid  = $OperationGuid
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
        Write-LogMessage -headers $Headers -API $APIName -message 'No valid cmdlets to process' -sev 'Warning' -tenant $TenantFilter
        $body = [pscustomobject]@{'Results' = @('No valid permission changes to process') }
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
            Write-LogMessage -headers $Headers -API $APIName -message "Executing bulk request with $($CmdletArray.Count) cmdlets" -Sev 'Info' -tenant $TenantFilter
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
                                Write-LogMessage -headers $Headers -API $APIName -message "Error for operation $operationGuid`: $ErrorMessage" -Sev 'Error' -tenant $TenantFilter
                            } else {
                                $null = $Results.Add($metadata.ExpectedResult)
                                $null = $SuccessfulOps.Add($metadata)
                                Write-LogMessage -headers $Headers -API $APIName -message "Success for operation $operationGuid`: $($metadata.ExpectedResult)" -Sev 'Info' -tenant $TenantFilter
                            }
                        } else {
                            Write-LogMessage -headers $Headers -API $APIName -message "Could not map result to operation. GUID: $operationGuid, Available GUIDs: $($GuidToMetadataMap.Keys -join ', ')" -sev 'Warning' -tenant $TenantFilter

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
                        $null = $SuccessfulOps.Add($CmdletMetadata)
                    }
                }
            }

            Write-LogMessage -headers $Headers -API $APIName -message 'Bulk request completed successfully' -Sev 'Info' -tenant $TenantFilter
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -message "Bulk request failed, using fallback: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter

            # Fallback to individual processing
            for ($i = 0; $i -lt $CmdletArray.Count; $i++) {
                $CmdletObj = $CmdletArray[$i]
                $CmdletMetadata = $CmdletMetadataArray[$i]
                try {
                    $null = New-ExoRequest -Anchor $CmdletMetadata.Mailbox -tenantid $TenantFilter -cmdlet $CmdletObj.CmdletInput.CmdletName -cmdParams $CmdletObj.CmdletInput.Parameters
                    $null = $Results.Add($CmdletMetadata.ExpectedResult)
                    $null = $SuccessfulOps.Add($CmdletMetadata)
                } catch {
                    $null = $Results.Add("Error processing $($CmdletMetadata.Permission) for $($CmdletMetadata.TargetUser) on $($CmdletMetadata.Mailbox): $($_.Exception.Message)")
                }
            }
        }
    } else {
        # Use individual processing for single operation
        $CmdletObj = $CmdletArray[0]
        $CmdletMetadata = $CmdletMetadataArray[0]
        try {
            $null = New-ExoRequest -Anchor $CmdletMetadata.Mailbox -tenantid $TenantFilter -cmdlet $CmdletObj.CmdletInput.CmdletName -cmdParams $CmdletObj.CmdletInput.Parameters
            $null = $Results.Add($CmdletMetadata.ExpectedResult)
            $null = $SuccessfulOps.Add($CmdletMetadata)
            Write-LogMessage -headers $Headers -API $APIName -message "Executed $($CmdletMetadata.Permission) permission modification" -Sev 'Info' -tenant $TenantFilter
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -message "Permission modification failed: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
            $null = $Results.Add("Error processing $($CmdletMetadata.Permission) for $($CmdletMetadata.TargetUser) on $($CmdletMetadata.Mailbox): $($_.Exception.Message)")
        }
    }

    # Keep the reporting DB cache in step with what actually changed. The bulk path bypasses
    # Set-CIPPMailboxPermission's own execute-mode sync (-AsCmdletObject returns early), so
    # without this the cached permission report goes stale after every bulk change.
    foreach ($Op in $SuccessfulOps) {
        if ($Op.Permission -in @('FullAccess', 'SendAs', 'SendOnBehalf')) {
            try {
                Sync-CIPPMailboxPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $Op.Mailbox -User $Op.TargetUser -PermissionType $Op.Permission -Action $Op.Action
            } catch {
                Write-Information "Cache sync warning: $($_.Exception.Message)"
            }
        }
    }

    $body = [pscustomobject]@{'Results' = @($Results) }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
