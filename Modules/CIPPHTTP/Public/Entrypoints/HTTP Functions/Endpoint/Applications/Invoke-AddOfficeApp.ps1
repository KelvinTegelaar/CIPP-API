function Invoke-AddOfficeApp {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    $Tenants = ($Request.Body.selectedTenants | Where-Object { $AllowedTenants -contains $_.customerId -or $AllowedTenants -contains 'AllTenants' }).defaultDomainName
    # Input bindings are passed in via param block.
    $Headers = $Request.Headers
    $APIName = $Request.Params.CIPPEndpoint
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }
    $AssignTo = $Request.Body.AssignTo -eq 'customGroup' ? $Request.Body.CustomGroup : $Request.Body.AssignTo
    $ExcludeGroup = $Request.Body.excludeGroup

    $Results = foreach ($Tenant in $Tenants) {
        try {
            # Office is a singleton per tenant, so match on the type rather than on a display name
            # that may have been changed after deployment.
            $ExistingO365 = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' -tenantid $Tenant | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.officeSuiteApp' }
            if (!$ExistingO365) {
                $ObjBody = Get-CIPPOfficeAppBody -Config $Request.Body
                if (-not $ObjBody) {
                    throw 'No Office configuration could be built from the supplied settings.'
                }
                Write-Host ($ObjBody | ConvertTo-Json -Compress)
                $OfficeAppID = New-graphPostRequest -Uri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' -tenantid $tenant -Body (ConvertTo-Json -InputObject $ObjBody -Depth 10) -type POST
            } else {
                "Office deployment already exists for $($Tenant)"
                continue
            }
            Write-LogMessage -headers $Headers -API $APIName -tenant $($Tenant) -message "Added Office profile to $($Tenant)" -Sev 'Info'
            if ($AssignTo -and $AssignTo -ne 'On') {
                Set-CIPPAssignedApplication -ApplicationId $OfficeAppID.id -TenantFilter $Tenant -Intent 'Required' -GroupName $AssignTo -ExcludeGroup $ExcludeGroup -APIName $APIName -Headers $Headers
                Write-LogMessage -headers $Headers -API $APIName -tenant $($Tenant) -message "Assigned Office to $AssignTo" -Sev 'Info'
            }
            "Successfully added Office App for $($Tenant)"
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Failed to add Office App for $($Tenant): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $($Tenant) -message "Failed to add Office App. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -Logdata $ErrorMessage
            continue
        }

    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = $Results }
        })
}
