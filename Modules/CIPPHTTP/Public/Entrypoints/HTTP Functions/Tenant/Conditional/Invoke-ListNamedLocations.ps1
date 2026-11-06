Function Invoke-ListNamedLocations {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.Read
    .DESCRIPTION
        Lists Conditional Access named locations (IP ranges and country-based locations) configured in a tenant. AllTenants reads the cached named locations from the reporting database, one row per location with its Tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.TenantFilter

    if ($TenantFilter -eq 'AllTenants') {
        try {
            $Rows = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'NamedLocations' -ByTenant
            $GraphRequest = foreach ($Tenant in $Rows.Keys) {
                foreach ($Row in $Rows[$Tenant]) {
                    foreach ($Location in @([CIPP.CippJson]::ConvertFromJson($Row.Data, $null))) {
                        $Properties = $Location.PSObject.Properties
                        $Properties.Add([psnoteproperty]::new('Tenant', $Tenant))
                        $Properties.Add([psnoteproperty]::new('CacheTimestamp', $Row.Timestamp))
                        $Properties.Add([psnoteproperty]::new('rangeOrLocation', $(if ($Location.ipRanges) { $Location.ipRanges.cidrAddress -join ', ' } else { $Location.countriesAndRegions -join ', ' })))
                        $Location
                    }
                }
            }
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $GraphRequest = $_.Exception.Message
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        }
    }

    try {
        $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -Tenantid $tenantfilter | Select-Object *,
        @{
            name       = 'rangeOrLocation'
            expression = { if ($_.ipRanges) { $_.ipranges.cidrAddress -join ', ' } else { $_.countriesAndRegions -join ', ' } }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = $ErrorMessage

    }
    return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        }

}
