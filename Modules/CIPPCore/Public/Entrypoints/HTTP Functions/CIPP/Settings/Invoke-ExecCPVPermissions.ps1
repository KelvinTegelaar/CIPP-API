using namespace System.Net

Function Invoke-ExecCPVPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $Tenant = Get-Tenants -IncludeAll | Where-Object -Property customerId -EQ $Request.Query.TenantFilter | Select-Object -First 1

    Write-Host "Our tenant is $($Tenant.displayName) - $($Tenant.defaultDomainName)"

    $TenantFilter = $Request.Query.TenantFilter
    $CPVConsentParams = @{
        TenantFilter = $Request.Query.TenantFilter
    }
    if ($Request.Query.ResetSP -eq 'true') {
        $CPVConsentParams.ResetSP = $true
    }

    $GraphRequest = try {
        if ($TenantFilter -ne 'PartnerTenant') {
            Set-CIPPCPVConsent @CPVConsentParams
        } else {
            $TenantFilter = $env:TenantId
        }
        Add-CIPPApplicationPermission -RequiredResourceAccess 'CippDefaults' -ApplicationId $ENV:ApplicationID -tenantfilter $TenantFilter
        Add-CIPPDelegatedPermission -RequiredResourceAccess 'CippDefaults' -ApplicationId $ENV:ApplicationID -tenantfilter $TenantFilter
        Set-CIPPSAMAdminRoles -TenantFilter $TenantFilter
        $Success = $true
    } catch {
        "Failed to update permissions for $($Tenant.displayName): $($_.Exception.Message)"
        $Success = $false
    }

    $Tenant = Get-Tenants -IncludeAll | Where-Object -Property customerId -EQ $TenantFilter | Select-Object -First 1

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results  = $GraphRequest
                Metadata = @{
                    Heading = ('CPV Permission - {0} ({1})' -f $Tenant.displayName, $Tenant.defaultDomainName)
                    Success = $Success
                }
            }
        })

}
