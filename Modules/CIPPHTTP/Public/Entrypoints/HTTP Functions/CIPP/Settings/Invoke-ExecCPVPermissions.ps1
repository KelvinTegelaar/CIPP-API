function Invoke-ExecCPVPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Body.tenantFilter

    $Tenant = Get-Tenants -TenantFilter $TenantFilter -IncludeErrors
    $StatusCode = [HttpStatusCode]::OK

    if ($Tenant) {
        Write-Host "Our tenant is $($Tenant.displayName) - $($Tenant.defaultDomainName)"

        $CPVConsentParams = @{
            TenantFilter = $TenantFilter
        }
        if ($Request.Query.ResetSP -eq $true) {
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
            $StatusCode = [HttpStatusCode]::InternalServerError
        }

        $Tenant = Get-Tenants -IncludeAll | Where-Object -Property customerId -EQ $TenantFilter | Select-Object -First 1

    } else {
        $GraphRequest = 'Tenant not found'
        $Success = $false
        $StatusCode = [HttpStatusCode]::NotFound
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{
                Results  = $GraphRequest
                Metadata = @{
                    Heading = ('CPV Permission - {0} ({1})' -f $Tenant.displayName, $Tenant.defaultDomainName)
                    Success = $Success
                }
            }
        })

}
