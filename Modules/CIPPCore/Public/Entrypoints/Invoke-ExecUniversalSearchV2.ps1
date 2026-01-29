function Invoke-ExecUniversalSearchV2 {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $SearchTerms = $Request.Query.searchTerms
    $Limit = if ($Request.Query.limit) { [int]$Request.Query.limit } else { 10 }

    $Results = Search-CIPPDbData -TenantFilter $TenantFilter -SearchTerms $SearchTerms -Types 'Users' -Limit $Limit

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Results)
    }

}
