function Invoke-ExecBulkLicense {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param (
        $Request,
        $TriggerMetadata
    )

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Results = [System.Collections.Generic.List[string]]::new()
    $StatusCode = [HttpStatusCode]::OK

    try {
        $UserRequests = $Request.Body
        $TenantGroups = $UserRequests | Group-Object -Property tenantFilter

        foreach ($TenantGroup in $TenantGroups) {
            $TenantFilter = $TenantGroup.Name
            $TenantRequests = $TenantGroup.Group

            # Initialize list for bulk license requests
            $LicenseRequests = [System.Collections.Generic.List[object]]::new()

            # Get unique user IDs for this tenant and normalize to a string array
            $UserIds = @(
                $TenantRequests |
                ForEach-Object {
                    if ($null -ne $_.userIds) {
                        @($_.userIds) | ForEach-Object { [string]$_ }
                    }
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
            )

            # Build OData filters in chunks to avoid Graph's OR clause limit
            $MaxUserIdFilterClauses = 15
            $UserLookupRequests = [System.Collections.Generic.List[object]]::new()
            $AllUsers = [System.Collections.Generic.List[object]]::new()

            for ($i = 0; $i -lt $UserIds.Count; $i += $MaxUserIdFilterClauses) {
                $EndIndex = [Math]::Min($i + $MaxUserIdFilterClauses - 1, $UserIds.Count - 1)
                $UserIdChunk = @($UserIds[$i..$EndIndex])
                $UserIdFilters = $UserIdChunk | ForEach-Object { "id eq '$_'" }
                $FilterQuery = $UserIdFilters -join ' or '

                $UserLookupRequests.Add(@{
                        id     = "UserLookup$i"
                        method = 'GET'
                        url    = "/users?`$filter=$FilterQuery&`$select=id,userPrincipalName,assignedLicenses&`$top=999"
                    })
            }

            # Fetch all user chunks in one Graph bulk request
            try {
                $UserLookupResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($UserLookupRequests)
            } catch {
                $LookupError = Get-CippException -Exception $_
                throw "Failed to lookup users before license assignment for tenant $TenantFilter. Error: $($LookupError.NormalizedError)"
            }
            foreach ($UserLookupResult in $UserLookupResults) {
                if ($UserLookupResult.status -lt 200 -or $UserLookupResult.status -gt 299) {
                    $LookupErrorMessage = $UserLookupResult.body.error.message
                    if ([string]::IsNullOrEmpty($LookupErrorMessage)) { $LookupErrorMessage = 'Unknown Graph batch error' }
                    throw "Failed to fetch users for chunk $($UserLookupResult.id): $LookupErrorMessage"
                }
                foreach ($ChunkUser in @($UserLookupResult.body.value)) {
                    $AllUsers.Add($ChunkUser)
                }
            }

            # Create lookup for quick access
            $UserLookup = @{}
            foreach ($User in $AllUsers) {
                $UserLookup[$User.id] = $User
            }

            # Process each user request
            foreach ($UserRequest in $TenantRequests) {
                $UserId = @($UserRequest.userIds | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
                if ($UserId.Count -eq 0) {
                    $Results.Add("No valid user ID found in request for tenant $TenantFilter")
                    continue
                }
                $UserId = $UserId[0]
                $User = $UserLookup[$UserId]
                if ($null -eq $User) {
                    $Results.Add("User $UserId not found in tenant $TenantFilter")
                    continue
                }
                $UserPrincipalName = $User.userPrincipalName
                $LicenseOperation = $UserRequest.LicenseOperation
                $RemoveAllLicenses = [bool]$UserRequest.RemoveAllLicenses
                $ReplaceAllLicenses = [bool]$UserRequest.ReplaceAllLicenses
                $Licenses = $UserRequest.Licenses | ForEach-Object { $_.value }
                $LicensesToRemove = $UserRequest.LicensesToRemove | ForEach-Object { $_.value }
                $LicensesToReplace = $UserRequest.LicensesToReplace | ForEach-Object { $_.value }

                # Handle license operations
                if ($LicenseOperation -eq 'Add') {
                    $AddLicenses = $Licenses
                    $RemoveLicenses = @()
                } elseif ($LicenseOperation -eq 'Remove') {
                    if ($RemoveAllLicenses) {
                        $RemoveLicenses = $User.assignedLicenses.skuId
                    } else {
                        # Only remove licenses the user actually has
                        $RemoveLicenses = $LicensesToRemove | Where-Object { $_ -in $User.assignedLicenses.skuId }
                    }
                    $AddLicenses = @()
                } elseif ($LicenseOperation -eq 'Replace') {
                    $AddLicenses = $Licenses
                    if ($ReplaceAllLicenses) {
                        # Replace all existing licenses with new ones
                        $RemoveLicenses = $User.assignedLicenses.skuId
                    } else {
                        # Only replace licenses the user actually has
                        $RemoveLicenses = $LicensesToReplace | Where-Object { $_ -in $User.assignedLicenses.skuId }
                    }
                }

                # Add to processing list if there are licenses to add or remove
                if ($AddLicenses.Count -gt 0 -or $RemoveLicenses.Count -gt 0) {
                    $LicenseRequests.Add([PSCustomObject]@{
                            UserId            = $UserId
                            UserPrincipalName = $UserPrincipalName
                            AddLicenses       = $AddLicenses
                            RemoveLicenses    = $RemoveLicenses
                            IsReplace         = ($LicenseOperation -eq 'Replace' -and $ReplaceAllLicenses)
                        })
                } else {
                    $Results.Add("No license changes needed for user $UserPrincipalName")
                }
            }

            # Process all license changes in bulk
            if ($LicenseRequests.Count -gt 0) {
                try {
                    $BulkResults = Set-CIPPUserLicense -LicenseRequests $LicenseRequests -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
                    foreach ($Result in $BulkResults) {
                        $Results.Add($Result)
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    $Results.Add("Failed to process bulk license operation for tenant $TenantFilter. Error: $($ErrorMessage.NormalizedError)")
                    Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to process bulk license operation. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                }
            }
        }

        $Body = @{
            Results = @($Results)
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{
            Results = @("Failed to process bulk license operation: $($ErrorMessage.NormalizedError)")
        }
        Write-LogMessage -API $APIName -message "Failed to process bulk license operation: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
    }

    # Return response
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
