function Invoke-PatchUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $HttpResponse = [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{'Results' = @('Default response, you should never see this.') }
    }

    try {
        # Handle array of user objects or single user object
        $Users = if ($Request.Body -is [array]) {
            $Request.Body
        } else {
            @($Request.Body)
        }

        # Validate that all users have required properties
        $InvalidUsers = $Users | Where-Object {
            [string]::IsNullOrWhiteSpace($_.id) -or [string]::IsNullOrWhiteSpace($_.tenantFilter)
        }
        if ($InvalidUsers.Count -gt 0) {
            $HttpResponse.StatusCode = [HttpStatusCode]::BadRequest
            $HttpResponse.Body = @{'Results' = @('Failed to patch user(s). Some users are missing id or tenantFilter') }
        } else {
            # Group users by tenant filter
            $UsersByTenant = $Users | Group-Object -Property tenantFilter

            $TotalPatchSuccessCount = 0
            $TotalManagerSuccessCount = 0
            $TotalSponsorSuccessCount = 0
            $AllErrorMessages = [System.Collections.Generic.List[string]]::new()
            $HasManagerUpdates = @($Users | Where-Object { -not [string]::IsNullOrWhiteSpace($_.manager) }).Count -gt 0
            $HasSponsorUpdates = @($Users | Where-Object { -not [string]::IsNullOrWhiteSpace($_.sponsor) }).Count -gt 0
            $HasRelationshipUpdates = $HasManagerUpdates -or $HasSponsorUpdates

            # Process each tenant separately
            foreach ($TenantGroup in $UsersByTenant) {
                $tenantFilter = $TenantGroup.Name
                $TenantUsers = $TenantGroup.Group
                $UsersWithManager = $TenantUsers | Where-Object { -not [string]::IsNullOrWhiteSpace($_.manager) }
                $ManagerGroups = $UsersWithManager | Group-Object -Property manager
                $UsersWithSponsor = $TenantUsers | Where-Object { -not [string]::IsNullOrWhiteSpace($_.sponsor) }
                $SponsorGroups = $UsersWithSponsor | Group-Object -Property sponsor

                # Build bulk requests for this tenant
                $int = 0
                $BulkRequests = [System.Collections.Generic.List[object]]::new()
                $BulkRequestUsers = [System.Collections.Generic.List[object]]::new()
                foreach ($User in $TenantUsers) {
                    # Remove routing and relationship properties from the body since they're not normal PATCH properties.
                    $PatchBody = $User | Select-Object -Property * -ExcludeProperty id, tenantFilter, manager, sponsor

                    if (@($PatchBody.PSObject.Properties).Count -eq 0) {
                        continue
                    }

                    $BulkRequest = @{
                        id        = ($int++).ToString()
                        method    = 'PATCH'
                        url       = "users/$($User.id)"
                        body      = $PatchBody
                        'headers' = @{
                            'Content-Type' = 'application/json'
                        }
                    }
                    [void]$BulkRequests.Add($BulkRequest)
                    [void]$BulkRequestUsers.Add($User)
                }

                # Execute bulk request for this tenant
                if ($BulkRequests.Count -gt 0) {
                    $BulkResults = New-GraphBulkRequest -tenantid $tenantFilter -Requests ($BulkRequests.ToArray())

                    # Process results for this tenant
                    foreach ($BulkResult in @($BulkResults)) {
                        $ResultIndex = [int]$BulkResult.id
                        $User = $BulkRequestUsers[$ResultIndex]

                        if ($BulkResult.status -eq 200 -or $BulkResult.status -eq 204) {
                            $TotalPatchSuccessCount++
                            Write-LogMessage -headers $Headers -API $APIName -tenant $tenantFilter -message "Successfully patched user $($User.id)" -Sev 'Info'
                        } else {
                            $ErrorMessage = if ($BulkResult.body.error.message) {
                                $BulkResult.body.error.message
                            } else {
                                "Unknown error (Status: $($BulkResult.status))"
                            }
                            [void]$AllErrorMessages.Add("Failed to patch user $($User.id) in tenant $($tenantFilter): $ErrorMessage")
                            Write-LogMessage -headers $Headers -API $APIName -tenant $tenantFilter -message "Failed to patch user $($User.id). Error: $ErrorMessage" -Sev 'Error'
                        }
                    }
                }

                foreach ($ManagerGroup in $ManagerGroups) {
                    $UserIds = @($ManagerGroup.Group | ForEach-Object { $_.id })
                    $ManagerUpn = $ManagerGroup.Name

                    try {
                        $ManagerResults = Set-CIPPManager -Users $UserIds -Manager $ManagerUpn -TenantFilter $tenantFilter -Headers $Headers -APIName $APIName

                        foreach ($ManagerResult in @($ManagerResults)) {
                            if ($ManagerResult.Success) {
                                $TotalManagerSuccessCount++
                            } else {
                                [void]$AllErrorMessages.Add("Failed to set manager for $($ManagerResult.User) in tenant $($tenantFilter): $($ManagerResult.Result)")
                            }
                        }
                    } catch {
                        foreach ($UserId in $UserIds) {
                            [void]$AllErrorMessages.Add("Failed to set manager for $UserId in tenant $($tenantFilter): $($_.Exception.Message)")
                        }
                    }
                }

                foreach ($SponsorGroup in $SponsorGroups) {
                    $UserIds = @($SponsorGroup.Group | ForEach-Object { $_.id })
                    $SponsorUpn = $SponsorGroup.Name

                    try {
                        $SponsorResults = Set-CIPPSponsor -Users $UserIds -Sponsor $SponsorUpn -TenantFilter $tenantFilter -Headers $Headers -APIName $APIName

                        foreach ($SponsorResult in @($SponsorResults)) {
                            if ($SponsorResult.Success) {
                                $TotalSponsorSuccessCount++
                            } else {
                                [void]$AllErrorMessages.Add("Failed to set sponsor for $($SponsorResult.User) in tenant $($tenantFilter): $($SponsorResult.Result)")
                            }
                        }
                    } catch {
                        foreach ($UserId in $UserIds) {
                            [void]$AllErrorMessages.Add("Failed to set sponsor for $UserId in tenant $($tenantFilter): $($_.Exception.Message)")
                        }
                    }
                }
            }

            # Build final response
            $TenantCount = ($Users | Select-Object -Property tenantFilter -Unique).Count
            $RelationshipResults = [System.Collections.Generic.List[string]]::new()
            if ($HasManagerUpdates) {
                [void]$RelationshipResults.Add("$TotalManagerSuccessCount manager assignment$(if($TotalManagerSuccessCount -ne 1){'s'})")
            }
            if ($HasSponsorUpdates) {
                [void]$RelationshipResults.Add("$TotalSponsorSuccessCount sponsor assignment$(if($TotalSponsorSuccessCount -ne 1){'s'})")
            }
            $RelationshipResultMessage = [string]::Join(' and ', $RelationshipResults.ToArray())

            $SuccessMessage = if ($HasRelationshipUpdates -and $TotalPatchSuccessCount -gt 0) {
                "Successfully patched $TotalPatchSuccessCount user$(if($TotalPatchSuccessCount -ne 1){'s'}) and updated $RelationshipResultMessage across $TenantCount tenant$(if($TenantCount -ne 1){'s'})"
            } elseif ($HasRelationshipUpdates) {
                "Successfully updated $RelationshipResultMessage across $TenantCount tenant$(if($TenantCount -ne 1){'s'})"
            } else {
                "Successfully patched $TotalPatchSuccessCount user$(if($TotalPatchSuccessCount -ne 1){'s'}) across $TenantCount tenant$(if($TenantCount -ne 1){'s'})"
            }

            if ($AllErrorMessages.Count -eq 0) {
                $HttpResponse.Body = @{'Results' = @($SuccessMessage) }
            } else {
                $HttpResponse.StatusCode = [HttpStatusCode]::BadRequest
                $PartialSuccessMessage = if ($HasRelationshipUpdates) { $SuccessMessage } else { "Successfully patched $TotalPatchSuccessCount of $($Users.Count) users" }
                $Results = [System.Collections.Generic.List[string]]::new()
                foreach ($ErrorMessage in $AllErrorMessages) {
                    [void]$Results.Add($ErrorMessage)
                }
                [void]$Results.Add($PartialSuccessMessage)
                $HttpResponse.Body = @{'Results' = @($Results.ToArray()) }
            }
        }

    } catch {
        $HttpResponse.StatusCode = [HttpStatusCode]::InternalServerError
        $HttpResponse.Body = @{'Results' = @("Failed to patch user(s). Error: $($_.Exception.Message)") }
    }

    return $HttpResponse
}
