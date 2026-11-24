function Invoke-ListCrossTenantAccess {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.Read
    .DESCRIPTION
        Lists a tenant's cross-tenant access settings: the default settings (isDefault) and each partner organisation with its own settings. Supports UseReportDB=true to read the reporting database cache, which AllTenants always uses.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # Serve from the reporting database cache instead of live Graph. AllTenants always reads the cache.
    $UseReportDB = $Request.Query.UseReportDB -eq $true -or $TenantFilter -eq 'AllTenants'

    try {
        if ($UseReportDB) {
            $Report = {
                param($Tenant)
                foreach ($Type in 'CrossTenantAccessPolicy', 'CrossTenantPartners') {
                    foreach ($Row in @(Get-CIPPDbItem -TenantFilter $Tenant -Type $Type)) {
                        if ($Row.RowKey -eq "$Type-Count") { continue }
                        $Item = try { [CIPP.CippJson]::ConvertFromJson($Row.Data, $null) } catch { continue }
                        $Item.PSObject.Properties.Add([psnoteproperty]::new('isDefault', $Type -eq 'CrossTenantAccessPolicy'))
                        $Item.PSObject.Properties.Add([psnoteproperty]::new('CacheTimestamp', $Row.Timestamp))
                        $Item
                    }
                }
            }
            # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
            $Page = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'CrossTenantAccessPolicy', 'CrossTenantPartners' -PageSize ($Request.Query.PageSize -as [int]) -ContinuationToken $Request.Query.nextLink -Report $Report
            if ($TenantFilter -ne 'AllTenants' -and @($Page.Results).Count -eq 0) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body       = @{ Results = 'No cached cross-tenant access settings for this tenant yet. Sync the data first.' }
                    })
            }
            # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
            $Body = if ($Request.Query.manualPagination -eq $true) { $Page } else { @($Page.Results) }
        } else {
            $Default = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default' -tenantid $TenantFilter
            $Default.PSObject.Properties.Add([psnoteproperty]::new('isDefault', $true))
            $Body = @(
                $Default
                foreach ($Partner in @(Get-CIPPCrossTenantPartner -TenantFilter $TenantFilter)) {
                    $Partner.PSObject.Properties.Add([psnoteproperty]::new('isDefault', $false))
                    $Partner
                }
            )
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Body = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
