function Invoke-ListTenantAlignment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        # Use the new Get-CIPPTenantAlignment function to get alignment data
        $AlignmentData = Get-CIPPTenantAlignment

        # Transform the data to match the expected API response format
        $Results = $AlignmentData | ForEach-Object {
            [PSCustomObject]@{
                tenantFilter             = $_.TenantFilter
                standardName             = $_.StandardName
                standardType             = $_.StandardType ? $_.StandardType : 'Classic Standard'
                standardId               = $_.StandardId
                alignmentScore           = $_.AlignmentScore
                LicenseMissingPercentage = $_.LicenseMissingPercentage
                combinedAlignmentScore   = $_.CombinedScore
                latestDataCollection     = $_.LatestDataCollection
            }
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($Results)
            })
    } catch {
        Write-LogMessage -API $APIName -message "Failed to get tenant alignment data: $($_.Exception.Message)" -sev Error
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ error = "Failed to get tenant alignment data: $($_.Exception.Message)" }
            })
    }
}
