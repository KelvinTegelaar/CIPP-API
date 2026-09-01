function Invoke-AddEdgeApp {
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
    $Headers = $Request.Headers
    $APIName = $Request.Params.CIPPEndpoint
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }
    $AssignTo = $Request.Body.AssignTo -eq 'customGroup' ? $Request.Body.CustomGroup : $Request.Body.AssignTo
    $ExcludeGroup = $Request.Body.excludeGroup

    $Results = foreach ($Tenant in $Tenants) {
        try {
            $ExistingEdge = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' -tenantid $Tenant | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.windowsMicrosoftEdgeApp' }
            if (!$ExistingEdge) {
                $ObjBody = Get-CIPPEdgeAppBody -Config $Request.Body
                if (-not $ObjBody) {
                    throw 'No Edge configuration could be built from the supplied settings.'
                }
                Write-Host ($ObjBody | ConvertTo-Json -Compress)
                $EdgeAppID = New-GraphPostRequest -Uri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' -tenantid $Tenant -Body (ConvertTo-Json -InputObject $ObjBody -Depth 10) -Type POST
            } else {
                "Edge deployment already exists for $($Tenant)"
                continue
            }
            Write-LogMessage -headers $Headers -API $APIName -tenant $($Tenant) -message "Added Edge app to $($Tenant)" -Sev 'Info'
            if ($AssignTo -and $AssignTo -ne 'On') {
                Set-CIPPAssignedApplication -ApplicationId $EdgeAppID.id -TenantFilter $Tenant -Intent 'Required' -GroupName $AssignTo -ExcludeGroup $ExcludeGroup -APIName $APIName -Headers $Headers
                Write-LogMessage -headers $Headers -API $APIName -tenant $($Tenant) -message "Assigned Edge to $AssignTo" -Sev 'Info'
            }
            "Successfully added Edge App for $($Tenant)"
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Failed to add Edge App for $($Tenant): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $($Tenant) -message "Failed to add Edge App. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -Logdata $ErrorMessage
            continue
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = $Results }
        })
}
