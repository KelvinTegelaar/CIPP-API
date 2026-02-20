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

            # Get unique user IDs for this tenant
            $UserIds = $TenantRequests.userIds | Select-Object -Unique

            # Build OData filter for specific users only
            $UserIdFilters = $UserIds | ForEach-Object { "id eq '$_'" }
            $FilterQuery = $UserIdFilters -join ' or '

            # Fetch only the users we need with server-side filtering
            $AllUsers = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=$FilterQuery&`$select=id,userPrincipalName,assignedLicenses&top=999" -tenantid $TenantFilter

            # Create lookup for quick access
            $UserLookup = @{}
            foreach ($User in $AllUsers) {
                $UserLookup[$User.id] = $User
            }

            # Process each user request
            foreach ($UserRequest in $TenantRequests) {
                $UserId = $UserRequest.userIds
                $User = $UserLookup[$UserId]
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
