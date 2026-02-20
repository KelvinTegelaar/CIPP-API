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
    $Type = if ($Request.Query.type) { $Request.Query.type } else { 'Users' }

    # Always search all tenants - do not pass TenantFilter parameter
    switch ($Type) {
        'Users' {
            $Results = Search-CIPPDbData -SearchTerms $SearchTerms -Types 'Users' -Limit $Limit -Properties 'id', 'userPrincipalName', 'displayName'
        }
        'Groups' {
            $Results = Search-CIPPDbData -SearchTerms $SearchTerms -Types 'Groups' -Limit $Limit -Properties 'id', 'displayName', 'mail', 'mailEnabled', 'securityEnabled', 'groupTypes', 'description'
        }
        default {
            $Results = Search-CIPPDbData -SearchTerms $SearchTerms -Types 'Users' -Limit $Limit -Properties 'id', 'userPrincipalName', 'displayName'
        }
    }

    Write-Information "Results: $($Results | ConvertTo-Json -Depth 10)"

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Results)
    }

}
