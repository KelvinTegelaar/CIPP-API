function Invoke-ExecLicenseSearch {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Resolves licence SKU ids to display names from the licence name table, falling back to the given tenant's cached licence overview. Takes an array of skuIds in the body.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $SkuIds = $Request.Body.skuIds

        if (-not $SkuIds -or $SkuIds.Count -eq 0) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{
                    error = 'No skuIds provided. Please provide an array of skuIds in the request body.'
                }
            }
        }

        # Tenant whose cached licence overview is checked for SKUs the name table does not hold yet
        $TenantFilter = $Request.Body.tenantFilter
        $OutputResults = @(Get-CIPPLicenseSkuName -SkuIds @($SkuIds) -TenantFilter $TenantFilter)

        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $OutputResults
        }

    } catch {
        Write-Information "Error occurred during license search: $($_.Exception.Message)"
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{
                error = "Failed to search for licenses: $($_.Exception.Message)"
            }
        }
    }
}
