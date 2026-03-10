function Invoke-ExecLicenseSearch {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        # Get skuIds from POST body
        $SkuIds = $Request.Body.skuIds

        if (-not $SkuIds -or $SkuIds.Count -eq 0) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{
                    error = 'No skuIds provided. Please provide an array of skuIds in the request body.'
                }
            }
        }

        Write-Information "Searching for licenses with skuIds: $($SkuIds -join ', ')"

        # Search for licenses using the skuIds as search terms
        # This searches across all tenants for matching licenses
        $Results = Search-CIPPDbData -SearchTerms $SkuIds -Types 'LicenseOverview' -Properties 'License', 'skuId'

        Write-Information "Found $($Results.Count) license records matching skuIds"

        # Initialize hashtable to store unique licenses by skuId
        $UniqueLicenses = @{}

        # Process each result and extract unique skuId/displayName pairs
        foreach ($Result in $Results) {
            if ($Result.Data -and $Result.Data.skuId) {
                $SkuIdKey = $Result.Data.skuId

                # Only add if we haven't seen this skuId yet
                if (-not $UniqueLicenses.ContainsKey($SkuIdKey)) {
                    $UniqueLicenses[$SkuIdKey] = [PSCustomObject]@{
                        skuId       = $Result.Data.skuId
                        displayName = $Result.Data.License
                    }
                }
            }
        }

        # Convert hashtable to array for output
        $OutputResults = @($UniqueLicenses.Values)

        Write-Information "Returning $($OutputResults.Count) unique licenses"

        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $OutputResults
        }

    } catch {
        Write-Information "Error occurred during license search: $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{
                error = "Failed to search for licenses: $($_.Exception.Message)"
            }
        }
    }
}
