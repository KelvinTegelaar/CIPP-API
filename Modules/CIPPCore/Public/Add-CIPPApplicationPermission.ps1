function Add-CIPPApplicationPermission {
    [CmdletBinding()]
    param(
        $RequiredResourceAccess,
        $TemplateId,
        $ApplicationId,
        $TenantFilter
    )
    if ($ApplicationId -eq $env:ApplicationID -and $TenantFilter -eq $env:TenantID) {
        $RequiredResourceAccess = 'CIPPDefaults'
    }
    if ($RequiredResourceAccess -eq 'CIPPDefaults') {

        $Permissions = Get-CippSamPermissions -NoDiff
        $RequiredResourceAccess = [System.Collections.Generic.List[object]]::new()

        foreach ($AppId in $Permissions.Permissions.PSObject.Properties.Name) {
            $AppPermissions = @($Permissions.Permissions.$AppId.applicationPermissions)
            $Resource = @{
                resourceAppId  = $AppId
                resourceAccess = [System.Collections.Generic.List[object]]::new()
            }
            foreach ($Permission in $AppPermissions) {
                $Resource.ResourceAccess.Add(@{
                        id   = $Permission.id
                        type = 'Role'
                    })
            }

            $RequiredResourceAccess.Add($Resource)
        }
    } else {
        if (!$RequiredResourceAccess -and $TemplateId) {
            Write-Information "Adding application permissions for template $TemplateId"
            $TemplateTable = Get-CIPPTable -TableName 'templates'
            $Filter = "RowKey eq '$TemplateId' and PartitionKey eq 'AppApprovalTemplate'"
            $Template = (Get-CIPPAzDataTableEntity @TemplateTable -Filter $Filter).JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
            $ApplicationId = $Template.AppId
            $Permissions = $Template.Permissions
            $RequiredResourceAccess = [System.Collections.Generic.List[object]]::new()
            foreach ($AppId in $Permissions.PSObject.Properties.Name) {
                $AppPermissions = @($Permissions.$AppId.applicationPermissions)
                $Resource = @{
                    resourceAppId  = $AppId
                    resourceAccess = [System.Collections.Generic.List[object]]::new()
                }
                foreach ($Permission in $AppPermissions) {
                    $Resource.ResourceAccess.Add(@{
                            id   = $Permission.id
                            type = 'Role'
                        })
                }

                $RequiredResourceAccess.Add($Resource)
            }
        }
    }

    Write-Information "Adding application permissions to application $ApplicationId in tenant $TenantFilter"

    $ServicePrincipalList = [System.Collections.Generic.List[object]]::new()
    $SPList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -skipTokenCache $true -tenantid $TenantFilter -NoAuthCheck $true
    foreach ($SP in $SPList) { $ServicePrincipalList.Add($SP) }
    $ourSVCPrincipal = $ServicePrincipalList | Where-Object -Property AppId -EQ $ApplicationId
    if (!$ourSVCPrincipal) {
        #Our Service Principal isn't available yet. We do a sleep and reexecute after 3 seconds.
        Start-Sleep -Seconds 5
        $ServicePrincipalList.Clear()
        $SPList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -skipTokenCache $true -tenantid $TenantFilter -NoAuthCheck $true
        foreach ($SP in $SPList) { $ServicePrincipalList.Add($SP) }
        $ourSVCPrincipal = $ServicePrincipalList | Where-Object -Property AppId -EQ $ApplicationId
    }

    $Results = [System.Collections.Generic.List[string]]::new()

    $CurrentRoles = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ourSVCPrincipal.id)/appRoleAssignments" -tenantid $TenantFilter -skipTokenCache $true -NoAuthCheck $true

    # Collect missing service principals and prepare bulk request
    $MissingServicePrincipals = [System.Collections.Generic.List[object]]::new()
    $AppIdToRequestId = @{}
    $requestId = 1

    foreach ($App in $RequiredResourceAccess) {
        $svcPrincipalId = $ServicePrincipalList | Where-Object -Property AppId -EQ $App.resourceAppId
        if (!$svcPrincipalId) {
            $Body = @{
                appId = $App.resourceAppId
            }
            $MissingServicePrincipals.Add(@{
                    id      = $requestId.ToString()
                    method  = 'POST'
                    url     = '/servicePrincipals'
                    headers = @{
                        'Content-Type' = 'application/json'
                    }
                    body    = $Body
                })
            $AppIdToRequestId[$App.resourceAppId] = $requestId.ToString()
            $requestId++
        }
    }

    # Create missing service principals in bulk
    if ($MissingServicePrincipals.Count -gt 0) {
        try {
            $BulkResults = New-GraphBulkRequest -Requests $MissingServicePrincipals -tenantid $TenantFilter -NoAuthCheck $true
            foreach ($Result in $BulkResults) {
                if ($Result.status -eq 201) {
                    $ServicePrincipalList.Add($Result.body)
                } else {
                    $AppId = ($MissingServicePrincipals | Where-Object { $_.id -eq $Result.id }).body.appId
                    $Results.add("Failed to create service principal for $($AppId): $($Result.body.error.message)")
                }
            }
        } catch {
            $Results.add("Failed to create service principals in bulk: $(Get-NormalizedError -message $_.Exception.Message)")
        }
    }

    # Build grants list
    $Grants = foreach ($App in $RequiredResourceAccess) {
        $svcPrincipalId = $ServicePrincipalList | Where-Object -Property AppId -EQ $App.resourceAppId
        if (!$svcPrincipalId) { continue }

        foreach ($SingleResource in $App.ResourceAccess | Where-Object -Property Type -EQ 'Role') {
            if ($SingleResource.id -in $CurrentRoles.appRoleId) { continue }
            [pscustomobject]@{
                principalId = $($ourSVCPrincipal.id)
                resourceId  = $($svcPrincipalId.id)
                appRoleId   = "$($SingleResource.Id)"
            }
        }
    }

    # Apply grants in bulk
    $counter = 0
    if ($Grants.Count -gt 0) {
        $GrantRequests = [System.Collections.Generic.List[object]]::new()
        $requestId = 1
        foreach ($Grant in $Grants) {
            $GrantRequests.Add(@{
                    id      = $requestId.ToString()
                    method  = 'POST'
                    url     = "/servicePrincipals/$($ourSVCPrincipal.id)/appRoleAssignedTo"
                    headers = @{
                        'Content-Type' = 'application/json'
                    }
                    body    = $Grant
                })
            $requestId++
        }

        try {
            $BulkResults = New-GraphBulkRequest -Requests $GrantRequests -tenantid $TenantFilter -NoAuthCheck $true
            foreach ($Result in $BulkResults) {
                if ($Result.status -eq 201) {
                    $counter++
                } else {
                    $GrantRequest = $GrantRequests | Where-Object { $_.id -eq $Result.id }
                    $Results.add("Failed to grant $($GrantRequest.body.appRoleId) to $($GrantRequest.body.resourceId): $($Result.body.error.message)")
                }
            }
        } catch {
            $Results.add("Failed to grant permissions in bulk: $(Get-NormalizedError -message $_.Exception.Message)")
        }
    }
    "Added $counter Application permissions to $($ourSVCPrincipal.displayName)"
    return $Results
}
