using namespace System.Net

Function Invoke-ListTenants {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Clear Cache
    if ($request.Query.ClearCache -eq 'true') {
        Remove-CIPPCache -tenantsOnly $request.query.TenantsOnly
        $GraphRequest = [pscustomobject]@{'Results' = 'Successfully completed request.' }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $GraphRequest
            })
        exit
    }

    try {
        $tenantfilter = $Request.Query.TenantFilter
        $Tenants = Get-Tenants -IncludeErrors

        if ($null -eq $TenantFilter -or $TenantFilter -eq 'null') {
            $TenantList = [system.collections.generic.list[object]]::new()
            if ($Request.Query.AllTenantSelector -eq $true) { 
                $TenantList.Add(@{
                        customerId        = 'AllTenants'
                        defaultDomainName = 'AllTenants'
                        displayName       = '*All Tenants'
                        domains           = 'AllTenants'
                        GraphErrorCount   = 0
                    }) | Out-Null

                if (($Tenants).length -gt 1) {
                    $TenantList.AddRange($Tenants) | Out-Null
                } elseif ($Tenants) {
                    $TenantList.Add($Tenants) | Out-Null
                }
                $body = $TenantList
            } else {
                $Body = $Tenants
            }
        } else {
            $body = $Tenants | Where-Object -Property defaultDomainName -EQ $Tenantfilter
        }

        Write-LogMessage -user $request.headers.'x-ms-client-principal' -tenant $Tenantfilter -API $APINAME -message 'Listed Tenant Details' -Sev 'Debug'
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -tenant $Tenantfilter -API $APINAME -message "List Tenant failed. The error is: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{ 
            'Results'         = "Failed to retrieve tenants: $($_.Exception.Message)"
            defaultDomainName = ''
            displayName       = 'Failed to retrieve tenants. Perform a permission check.'
            customerId        = ''

        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Body)
        })
    

}
