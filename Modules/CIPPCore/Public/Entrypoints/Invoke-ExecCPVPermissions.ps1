using namespace System.Net

Function Invoke-ExecCPVPermissions {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $TenantFilter = (get-tenants -IncludeAll -IncludeErrors | Where-Object -Property customerId -EQ $Request.query.Tenantfilter).defaultDomainName
    Write-Host "Our Tenantfilter is $TenantFilter"

    $CPVConsentParams = @{
        Tenantfilter = $TenantFilter
    }
    if ($Request.Query.ResetSP -eq 'true') {
        $CPVConsentParams.ResetSP = $true
    }

    $GraphRequest = try {
        Set-CIPPCPVConsent @CPVConsentParams
        Add-CIPPApplicationPermission -RequiredResourceAccess 'CippDefaults' -ApplicationId $ENV:ApplicationID -tenantfilter $TenantFilter
        Add-CIPPDelegatedPermission -RequiredResourceAccess 'CippDefaults' -ApplicationId $ENV:ApplicationID -tenantfilter $TenantFilter
        $Success = $true
    } catch {
        "Failed to update permissions for $($TenantFilter): $($_.Exception.Message)"
        $Success = $false
    }

    $Tenant = Get-Tenants -IncludeAll -IncludeErrors | Where-Object -Property defaultDomainName -EQ $Tenantfilter

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results  = $GraphRequest
                Metadata = @{
                    Heading = 'CPV Permission - {0} ({1})' -f $Tenant.displayName, $Tenant.defaultDomainName
                    Success = $Success
                }
            }
        })

}
