function Invoke-ExecUniversalSearchV2 {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $SearchTerms = $Request.Query.searchTerms
    $Limit = if ($Request.Query.limit) { [int]$Request.Query.limit } else { 10 }

    # Always search all tenants - do not pass TenantFilter parameter
    $Results = Search-CIPPDbData -SearchTerms $SearchTerms -Types 'Users' -Limit $Limit -UserProperties 'id', 'userPrincipalName', 'displayName'


    Write-Information "Results: $($Results | ConvertTo-Json -Depth 10)"

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Results)
    }

}
