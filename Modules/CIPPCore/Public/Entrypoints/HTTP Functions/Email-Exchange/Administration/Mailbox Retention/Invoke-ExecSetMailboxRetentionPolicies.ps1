using namespace System.Net

Function Invoke-ExecSetMailboxRetentionPolicies {
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
    Write-LogMessage -headers $Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Results = [System.Collections.Generic.List[string]]::new()
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.body.tenantFilter
    $CmdletArray = [System.Collections.ArrayList]::new()
    $CmdletMetadataArray = [System.Collections.ArrayList]::new()
    $GuidToMetadataMap = @{}

    if ([string]::IsNullOrEmpty($TenantFilter)) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = "Tenant filter is required"
        })
        return
    }

    try {
        $PolicyName = $Request.body.PolicyName
        $Mailboxes = $Request.body.Mailboxes

        # Validate required parameters
        if ([string]::IsNullOrEmpty($PolicyName)) {
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = "PolicyName is required"
            })
            return
        }

        if (-not $Mailboxes -or $Mailboxes.Count -eq 0) {
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = "Mailboxes array is required"
            })
            return
        }

        # Helper function to add cmdlet to bulk array
        function Add-BulkCmdlet {
            param($CmdletName, $Parameters, $MailboxIdentity)

            $OperationGuid = [Guid]::NewGuid().ToString()

            $CmdletObj = @{
                CmdletInput = @{
                    CmdletName = $CmdletName
                    Parameters = $Parameters
                }
                OperationGuid = $OperationGuid
            }

            $CmdletMetadata = [PSCustomObject]@{
                MailboxIdentity = $MailboxIdentity
                OperationGuid = $OperationGuid
            }

            $null = $CmdletArray.Add($CmdletObj)
            $null = $CmdletMetadataArray.Add($CmdletMetadata)
            $GuidToMetadataMap[$OperationGuid] = $CmdletMetadata
        }

        # Process each mailbox
        foreach ($MailboxIdentity in $Mailboxes) {
            if ([string]::IsNullOrEmpty($MailboxIdentity)) {
                $Results.Add("Failed to apply retention policy to empty mailbox identity")
                continue
            }

            Add-BulkCmdlet -CmdletName 'Set-Mailbox' -Parameters @{Identity = $MailboxIdentity; RetentionPolicy = $PolicyName} -MailboxIdentity $MailboxIdentity
        }

        # Execute bulk operations
        if ($CmdletArray.Count -gt 0) {
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Applying retention policy '$PolicyName' to $($CmdletArray.Count) mailboxes" -Sev 'Info' -tenant $TenantFilter

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
                                    $Message = "Failed to apply retention policy '$PolicyName' to $($metadata.MailboxIdentity): $ErrorMessage"
                                    Write-LogMessage -headers $Request.Headers -API $APINAME -message $Message -Sev 'Error' -tenant $TenantFilter
                                    $Results.Add($Message)
                                } else {
                                    $Message = "Successfully applied retention policy '$PolicyName' to $($metadata.MailboxIdentity)"
                                    Write-LogMessage -headers $Request.Headers -API $APINAME -message $Message -Sev 'Info' -tenant $TenantFilter
                                    $Results.Add($Message)
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
                    $Message = "Successfully applied retention policy '$PolicyName' to $($CmdletMetadata.MailboxIdentity)"
                    Write-LogMessage -headers $Request.Headers -API $APINAME -message $Message -Sev 'Info' -tenant $TenantFilter
                    $Results.Add($Message)
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    $Message = "Failed to apply retention policy '$PolicyName' to $($CmdletMetadata.MailboxIdentity): $ErrorMessage"
                    Write-LogMessage -headers $Request.Headers -API $APINAME -message $Message -Sev 'Error' -tenant $TenantFilter
                    $Results.Add($Message)
                }
            }
        }

        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $Message = "Failed to set mailbox retention policies: $ErrorMessage"
        Write-LogMessage -headers $Request.Headers -API $APINAME -message $Message -Sev 'Error' -tenant $TenantFilter
        $Results.Add($Message)
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Results) }
    })
}
