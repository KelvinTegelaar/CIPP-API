Function Invoke-ExecManageRetentionTags {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.RetentionPolicies.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Results = [System.Collections.Generic.List[string]]::new()
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.body.tenantFilter
    $CmdletArray = [System.Collections.ArrayList]::new()
    $CmdletMetadataArray = [System.Collections.ArrayList]::new()
    $GuidToMetadataMap = @{}

    if ([string]::IsNullOrEmpty($TenantFilter)) {
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = "Tenant filter is required"
        })
        return
    }

    try {
        # Helper function to add cmdlet to bulk array
        function Add-BulkCmdlet {
            param($CmdletName, $Parameters, $ExpectedResult, $Operation, $Identity = "")

            $OperationGuid = [Guid]::NewGuid().ToString()

            $CmdletObj = @{
                CmdletInput = @{
                    CmdletName = $CmdletName
                    Parameters = $Parameters
                }
                OperationGuid = $OperationGuid
            }

            $CmdletMetadata = [PSCustomObject]@{
                ExpectedResult = $ExpectedResult
                Operation = $Operation
                Identity = $Identity
                OperationGuid = $OperationGuid
            }

            $null = $CmdletArray.Add($CmdletObj)
            $null = $CmdletMetadataArray.Add($CmdletMetadata)
            $GuidToMetadataMap[$OperationGuid] = $CmdletMetadata
        }

        # Validation function for retention tag parameters
        function Test-RetentionTagParams {
            param($Tag, $IsModification = $false)

            if (-not $IsModification) {
                if ([string]::IsNullOrEmpty($Tag.Name)) {
                    return "Tag Name is required"
                }

                if ([string]::IsNullOrEmpty($Tag.Type)) {
                    return "Tag Type is required"
                }

                # Valid tag types
                $validTypes = @('All', 'Inbox', 'SentItems', 'DeletedItems', 'Drafts', 'Outbox', 'JunkEmail', 'Journal', 'SyncIssues', 'ConversationHistory', 'Personal', 'RecoverableItems', 'NonIpmRoot', 'LegacyArchiveJournals', 'Clutter', 'Calendar', 'Notes', 'Tasks', 'Contacts', 'RssSubscriptions', 'ManagedCustomFolder')
                if ($Tag.Type -notin $validTypes) {
                    return "Invalid Type '$($Tag.Type)'. Valid types: $($validTypes -join ', ')"
                }

                # Validate RetentionAction compatibility with Type (only for creation)
                if ($Tag.RetentionAction) {
                    switch ($Tag.RetentionAction) {
                        'MoveToArchive' {
                            $allowedTypesForArchive = @('All', 'Personal', 'RecoverableItems')
                            if ($Tag.Type -notin $allowedTypesForArchive) {
                                return "RetentionAction 'MoveToArchive' can only be used with tag types: $($allowedTypesForArchive -join ', '). Current type: '$($Tag.Type)'"
                            }
                        }
                        'DeleteAndAllowRecovery' {
                            $excludedTypesForDelete = @('RecoverableItems')
                            if ($Tag.Type -in $excludedTypesForDelete) {
                                return "RetentionAction 'DeleteAndAllowRecovery' cannot be used with tag type '$($Tag.Type)'"
                            }
                        }
                        'PermanentlyDelete' {
                            $excludedTypesForPermanentDelete = @('RecoverableItems')
                            if ($Tag.Type -in $excludedTypesForPermanentDelete) {
                                return "RetentionAction 'PermanentlyDelete' cannot be used with tag type '$($Tag.Type)'"
                            }
                        }
                    }
                }

                # Validate RetentionEnabled and RetentionAction relationship (only for creation)
                if ($Tag.RetentionEnabled -eq $true -and [string]::IsNullOrEmpty($Tag.RetentionAction)) {
                    return "RetentionAction is required when RetentionEnabled is set to true"
                }
            }

            # Common validations for both create and modify
            if ($Tag.Name) {
                if ($Tag.Name -match '[\\/:*?\"<>|]') {
                    return "Tag name contains invalid characters. Avoid using: \ / : * ? `" < > |"
                }

                if ($Tag.Name.Length -gt 64) {
                    return "Tag name cannot exceed 64 characters"
                }
            }

            if ($Tag.RetentionAction) {
                $validActions = @('DeleteAndAllowRecovery', 'PermanentlyDelete', 'MoveToArchive', 'MarkAsPastRetentionLimit')
                if ($Tag.RetentionAction -notin $validActions) {
                    return "Invalid RetentionAction '$($Tag.RetentionAction)'. Valid actions: $($validActions -join ', ')"
                }
            }

            if ($Tag.AgeLimitForRetention -and ($Tag.AgeLimitForRetention -lt 0 -or $Tag.AgeLimitForRetention -gt 24855)) {
                return "AgeLimitForRetention must be between 0 and 24855 days"
            }

            return $null
        }

        # Create Retention Tags
        $CreateTags = $Request.body.CreateTags
        if ($CreateTags) {
            foreach ($Tag in $CreateTags) {
                $validationError = Test-RetentionTagParams -Tag $Tag -IsModification $false
                if ($validationError) {
                    $Results.Add("Failed to create tag '$($Tag.Name)': $validationError")
                    continue
                }

                $cmdParams = @{
                    Name = $Tag.Name
                    Type = $Tag.Type
                }

                if ($Tag.AgeLimitForRetention) {
                    $cmdParams.AgeLimitForRetention = $Tag.AgeLimitForRetention
                }

                if ($Tag.RetentionAction) {
                    $cmdParams.RetentionAction = $Tag.RetentionAction
                }

                if ($Tag.Comment) {
                    $cmdParams.Comment = $Tag.Comment
                }

                if ($Tag.RetentionEnabled -ne $null) {
                    $cmdParams.RetentionEnabled = $Tag.RetentionEnabled
                }

                if ($Tag.LocalizedComment) {
                    $cmdParams.LocalizedComment = $Tag.LocalizedComment
                }

                if ($Tag.LocalizedRetentionPolicyTagName) {
                    $cmdParams.LocalizedRetentionPolicyTagName = $Tag.LocalizedRetentionPolicyTagName
                }

                $resultParts = [System.Collections.ArrayList]::new()
                $null = $resultParts.Add("Successfully created retention tag: $($Tag.Name) (Type: $($Tag.Type)")
                if ($Tag.RetentionAction) { $null = $resultParts.Add(", Action: $($Tag.RetentionAction)") }
                if ($Tag.AgeLimitForRetention) { $null = $resultParts.Add(", Age: $($Tag.AgeLimitForRetention) days") }
                $null = $resultParts.Add(")")
                $expectedResult = $resultParts -join ""

                Add-BulkCmdlet -CmdletName 'New-RetentionPolicyTag' -Parameters $cmdParams -ExpectedResult $expectedResult -Operation 'Create' -Identity $Tag.Name
            }
        }

        # Modify Retention Tags
        $ModifyTags = $Request.body.ModifyTags
        if ($ModifyTags) {
            foreach ($Tag in $ModifyTags) {
                if ([string]::IsNullOrEmpty($Tag.Identity)) {
                    $Results.Add("Failed to modify tag - Identity is required")
                    continue
                }

                # Use basic validation for modifications
                $validationError = Test-RetentionTagParams -Tag $Tag -IsModification $true
                if ($validationError) {
                    $Results.Add("Failed to modify tag '$($Tag.Identity)': $validationError")
                    continue
                }

                $cmdParams = @{
                    Identity = $Tag.Identity
                }

                if ($Tag.Name) {
                    $cmdParams.Name = $Tag.Name
                }

                if ($Tag.AgeLimitForRetention) {
                    $cmdParams.AgeLimitForRetention = $Tag.AgeLimitForRetention
                }

                if ($Tag.RetentionAction) {
                    $cmdParams.RetentionAction = $Tag.RetentionAction
                }

                if ($Tag.Comment) {
                    $cmdParams.Comment = $Tag.Comment
                }

                if ($Tag.RetentionEnabled -ne $null) {
                    $cmdParams.RetentionEnabled = $Tag.RetentionEnabled
                }

                if ($Tag.LocalizedComment) {
                    $cmdParams.LocalizedComment = $Tag.LocalizedComment
                }

                if ($Tag.LocalizedRetentionPolicyTagName) {
                    $cmdParams.LocalizedRetentionPolicyTagName = $Tag.LocalizedRetentionPolicyTagName
                }

                Add-BulkCmdlet -CmdletName 'Set-RetentionPolicyTag' -Parameters $cmdParams -ExpectedResult "Successfully modified retention tag: $($Tag.Identity)" -Operation 'Modify' -Identity $Tag.Identity
            }
        }

        # Delete Retention Tags
        $DeleteTags = $Request.body.DeleteTags
        if ($DeleteTags) {
            foreach ($TagIdentity in $DeleteTags) {
                if ([string]::IsNullOrEmpty($TagIdentity)) {
                    $Results.Add("Failed to delete tag - Identity is required")
                    continue
                }

                # Check if tag is used in any retention policies
                $AllPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionPolicy' -ErrorAction SilentlyContinue
                $policiesUsingTag = $AllPolicies | Where-Object {
                    $_.RetentionPolicyTagLinks -contains $TagIdentity
                }

                if ($policiesUsingTag) {
                    $policyNames = ($policiesUsingTag | ForEach-Object { $_.Name }) -join ', '
                    $Results.Add("Cannot delete retention tag '$TagIdentity' - still used in policies: $policyNames")
                    continue
                }

                Add-BulkCmdlet -CmdletName 'Remove-RetentionPolicyTag' -Parameters @{Identity = $TagIdentity; Confirm = $false} -ExpectedResult "Successfully deleted retention tag: $TagIdentity" -Operation 'Delete' -Identity $TagIdentity
            }
        }

        # Execute bulk operations
        if ($CmdletArray.Count -gt 0) {
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Executing $($CmdletArray.Count) retention tag operations" -Sev 'Info' -tenant $TenantFilter

            if ($CmdletArray.Count -gt 1) {
                # Use bulk processing
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
                                    $Message = "Failed to $($metadata.Operation.ToLower()) retention tag $($metadata.Identity): $ErrorMessage"
                                    Write-LogMessage -headers $Request.Headers -API $APINAME -message $Message -Sev 'Error' -tenant $TenantFilter
                                    $Results.Add($Message)
                                } else {
                                    Write-LogMessage -headers $Request.Headers -API $APINAME -message $metadata.ExpectedResult -Sev 'Info' -tenant $TenantFilter
                                    $Results.Add($metadata.ExpectedResult)
                                }
                            }
                        }
                    }
                }
            } else {
                # Single operation
                $CmdletObj = $CmdletArray[0]
                $CmdletMetadata = $CmdletMetadataArray[0]

                try {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $CmdletObj.CmdletInput.CmdletName -cmdParams $CmdletObj.CmdletInput.Parameters
                    Write-LogMessage -headers $Request.Headers -API $APINAME -message $CmdletMetadata.ExpectedResult -Sev 'Info' -tenant $TenantFilter
                    $Results.Add($CmdletMetadata.ExpectedResult)
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    $Message = "Failed to $($CmdletMetadata.Operation.ToLower()) retention tag $($CmdletMetadata.Identity): $ErrorMessage"
                    Write-LogMessage -headers $Request.Headers -API $APINAME -message $Message -Sev 'Error' -tenant $TenantFilter
                    $Results.Add($Message)
                }
            }
        }

        $StatusCode = [HttpStatusCode]::OK

        # Simple response logic
        if ($CreateTags -or $ModifyTags -or $DeleteTags) {
            # For any operations, return the results messages
            $GraphRequest = @($Results)
        } else {
            # For listing, return all tags or specific tag - wrapped in try-catch
            try {
                $SpecificName = $Request.Query.name
                if ($SpecificName) {
                    # Get specific tag by name
                    $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionPolicyTag' -cmdParams @{Identity = $SpecificName}
                } else {
                    # Get all tags
                    $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionPolicyTag'
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $Message = if ($Request.Query.name) {
                    "Failed to retrieve retention tag '$($Request.Query.name)': $ErrorMessage"
                } else {
                    "Failed to retrieve retention tags: $ErrorMessage"
                }
                Write-LogMessage -headers $Request.Headers -API $APINAME -message $Message -Sev 'Error' -tenant $TenantFilter
                $Results.Add($Message)
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = @($Results)
            }
        }

        # If no results are found, we will return an empty message to prevent null reference errors in the frontend
        $GraphRequest = $GraphRequest ?? @()

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $Message = "Failed to manage retention tags: $ErrorMessage"
        Write-LogMessage -headers $Request.Headers -API $APINAME -message $Message -Sev 'Error' -tenant $TenantFilter
        $Results.Add($Message)
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = @($Results)
    }

    # If no results are found, we will return an empty message to prevent null reference errors in the frontend
    $GraphRequest = $GraphRequest ?? @()

    return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $GraphRequest
    })
}
