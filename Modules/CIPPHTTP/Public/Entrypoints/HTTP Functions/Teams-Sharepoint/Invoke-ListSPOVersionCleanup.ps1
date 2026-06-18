function Invoke-ListSPOVersionCleanup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $SiteUrl = $Request.Query.SiteUrl ?? $Request.Body.SiteUrl

    try {
        $Result = Get-CIPPSiteVersionCleanupStatus -TenantFilter $TenantFilter -SiteUrl $SiteUrl
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Retrieved version cleanup status for $SiteUrl" -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Failed to retrieve version cleanup status for $SiteUrl : $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $Result = "Failed to retrieve version cleanup status: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    }
}
