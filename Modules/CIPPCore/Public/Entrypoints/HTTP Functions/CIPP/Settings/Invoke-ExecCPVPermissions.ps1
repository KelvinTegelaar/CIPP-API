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

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'
    $TenantFilter = $Request.Body.tenantFilter

    $Tenant = Get-Tenants -IncludeAll | Where-Object -Property customerId -EQ $TenantFilter | Select-Object -First 1

    if ($Tenant) {
        Write-Host "Our tenant is $($Tenant.displayName) - $($Tenant.defaultDomainName)"

        $CPVConsentParams = @{
            TenantFilter = $TenantFilter
        }
        if ($Request.Query.ResetSP -eq 'true') {
            $CPVConsentParams.ResetSP = $true
        }

        $GraphRequest = try {
            if ($TenantFilter -notin @('PartnerTenant', $env:TenantID)) {
                Set-CIPPCPVConsent @CPVConsentParams
            } else {
                $TenantFilter = $env:TenantID
                $Tenant = [PSCustomObject]@{
                    displayName       = '*Partner Tenant'
                    defaultDomainName = $env:TenantID
                }
            }
            Add-CIPPApplicationPermission -RequiredResourceAccess 'CIPPDefaults' -ApplicationId $env:ApplicationID -tenantfilter $TenantFilter
            Add-CIPPDelegatedPermission -RequiredResourceAccess 'CIPPDefaults' -ApplicationId $env:ApplicationID -tenantfilter $TenantFilter
            if ($TenantFilter -notin @('PartnerTenant', $env:TenantID)) {
                Set-CIPPSAMAdminRoles -TenantFilter $TenantFilter
            }
            $Success = $true
        } catch {
            "Failed to update permissions for $($Tenant.displayName): $($_.Exception.Message)"
            $Success = $false
        }

        $Tenant = Get-Tenants -IncludeAll | Where-Object -Property customerId -EQ $TenantFilter | Select-Object -First 1

    } else {
        $GraphRequest = 'Tenant not found'
        $Success = $false
    }
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
