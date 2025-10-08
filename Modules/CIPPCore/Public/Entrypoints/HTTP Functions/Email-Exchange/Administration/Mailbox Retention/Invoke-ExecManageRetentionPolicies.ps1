Function Invoke-ExecManageRetentionPolicies {
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

        # Create Retention Policies
        $CreatePolicies = $Request.body.CreatePolicies
        if ($CreatePolicies) {
            foreach ($Policy in $CreatePolicies) {
                if ([string]::IsNullOrEmpty($Policy.Name)) {
                    $Results.Add("Failed to create policy - Name is required")
                    continue
                }

                $cmdParams = @{
                    Name = $Policy.Name
                }

                if ($Policy.RetentionPolicyTagLinks) {
                    $cmdParams.RetentionPolicyTagLinks = $Policy.RetentionPolicyTagLinks
                }

                Add-BulkCmdlet -CmdletName 'New-RetentionPolicy' -Parameters $cmdParams -ExpectedResult "Successfully created retention policy: $($Policy.Name)" -Operation 'Create' -Identity $Policy.Name
            }
        }

        # Modify Retention Policies
        $ModifyPolicies = $Request.body.ModifyPolicies
        if ($ModifyPolicies) {
            foreach ($Policy in $ModifyPolicies) {
                if ([string]::IsNullOrEmpty($Policy.Identity)) {
                    $Results.Add("Failed to modify policy - Identity is required")
                    continue
                }

                $cmdParams = @{
                    Identity = $Policy.Identity
                }

                if ($Policy.Name) {
                    $cmdParams.Name = $Policy.Name
                }

                # Handle tag modifications - need to get current policy first for add/remove operations
                if ($Policy.AddTags -or $Policy.RemoveTags) {
                    try {
                        $currentPolicy = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionPolicy' -cmdParams @{Identity = $Policy.Identity}
                        $currentTags = $currentPolicy.RetentionPolicyTagLinks
                    } catch {
                        $Results.Add("Failed to modify policy $($Policy.Identity) - Could not retrieve current policy")
                        continue
                    }

                    if ($Policy.AddTags) {
                        $newTagsList = [System.Collections.ArrayList]::new()
                        if ($currentTags) {
                            foreach ($tag in $currentTags) { $null = $newTagsList.Add($tag) }
                        }
                        foreach ($tag in $Policy.AddTags) {
                            if ($tag -notin $newTagsList) { $null = $newTagsList.Add($tag) }
                        }
                        $cmdParams.RetentionPolicyTagLinks = @($newTagsList)
                    }

                    if ($Policy.RemoveTags) {
                        $newTagsList = [System.Collections.ArrayList]::new()
                        if ($currentTags) {
                            foreach ($tag in $currentTags) {
                                if ($tag -notin $Policy.RemoveTags) { $null = $newTagsList.Add($tag) }
                            }
                        }
                        $cmdParams.RetentionPolicyTagLinks = @($newTagsList)
                    }
                } elseif ($Policy.RetentionPolicyTagLinks) {
                    $cmdParams.RetentionPolicyTagLinks = $Policy.RetentionPolicyTagLinks
                }

                Add-BulkCmdlet -CmdletName 'Set-RetentionPolicy' -Parameters $cmdParams -ExpectedResult "Successfully modified retention policy: $($Policy.Identity)" -Operation 'Modify' -Identity $Policy.Identity
            }
        }

        # Delete Retention Policies
        $DeletePolicies = $Request.body.DeletePolicies
        if ($DeletePolicies) {
            foreach ($PolicyIdentity in $DeletePolicies) {
                if ([string]::IsNullOrEmpty($PolicyIdentity)) {
                    $Results.Add("Failed to delete policy - Identity is required")
                    continue
                }

                # Check if policy is assigned to mailboxes (do this before bulk processing)
                $assignedMailboxes = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{
                    Filter = "RetentionPolicy -eq '$PolicyIdentity'"
                    ResultSize = 1
                } -ErrorAction SilentlyContinue

                if ($assignedMailboxes) {
                    $Results.Add("Cannot delete retention policy $PolicyIdentity - still assigned to mailboxes")
                    continue
                }

                Add-BulkCmdlet -CmdletName 'Remove-RetentionPolicy' -Parameters @{Identity = $PolicyIdentity; Confirm = $false} -ExpectedResult "Successfully deleted retention policy: $PolicyIdentity" -Operation 'Delete' -Identity $PolicyIdentity
            }
        }

        # Execute bulk operations
        if ($CmdletArray.Count -gt 0) {
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Executing $($CmdletArray.Count) retention policy operations" -Sev 'Info' -tenant $TenantFilter

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
                                    $Message = "Failed to $($metadata.Operation.ToLower()) retention policy $($metadata.Identity): $ErrorMessage"
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
                    $Message = "Failed to $($CmdletMetadata.Operation.ToLower()) retention policy $($CmdletMetadata.Identity): $ErrorMessage"
                    Write-LogMessage -headers $Request.Headers -API $APINAME -message $Message -Sev 'Error' -tenant $TenantFilter
                    $Results.Add($Message)
                }
            }
        }

        $StatusCode = [HttpStatusCode]::OK

        # Simple response logic
        if ($CreatePolicies -or $ModifyPolicies -or $DeletePolicies) {
            # For any operations, return the results messages
            $GraphRequest = @($Results)
        } else {
            # For listing, return all policies or specific policy - wrapped in try-catch
            try {
                $SpecificName = $Request.Query.name
                if ($SpecificName) {
                    # Get specific policy by name
                    $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionPolicy' -cmdParams @{Identity = $SpecificName}
                } else {
                    # Get all policies
                    $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionPolicy'
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $Message = if ($Request.Query.name) {
                    "Failed to retrieve retention policy '$($Request.Query.name)': $ErrorMessage"
                } else {
                    "Failed to retrieve retention policies: $ErrorMessage"
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
        $Message = "Failed to manage retention policies: $ErrorMessage"
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
