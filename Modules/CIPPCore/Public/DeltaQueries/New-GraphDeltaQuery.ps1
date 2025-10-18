function New-GraphDeltaQuery {
    <#
    .SYNOPSIS
        Creates a new Graph Delta Query.
    .DESCRIPTION
        This function creates a new Graph Delta Query to track changes in a specified resource.
        Always returns the full response including the deltaLink for future incremental queries.
    .PARAMETER Resource
        The resource to track changes for (e.g., 'users', 'groups').
    .PARAMETER TenantFilter
        The tenant to filter the query on.
    .PARAMETER Parameters
        Additional query parameters (e.g., $select, $filter, $top).
    .PARAMETER DeltaUrl
        Use this parameter to continue a delta query with a specific delta or next link.
    #>
    [CmdletBinding(DefaultParameterSetName = 'NewDeltaQuery')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'NewDeltaQuery')]
        [Parameter(Mandatory = $true, ParameterSetName = 'DeltaUrl')]
        [string]$TenantFilter,

        [Parameter(ParameterSetName = 'NewDeltaQuery', Mandatory = $true)]
        [ValidateSet('users', 'groups', 'contacts', 'devices', 'applications', 'servicePrincipals', 'directoryObjects', 'administrativeUnits')]
        [string]$Resource,

        [Parameter(ParameterSetName = 'NewDeltaQuery', Mandatory = $false)]
        [hashtable]$Parameters = @{},

        [Parameter(ParameterSetName = 'DeltaUrl', Mandatory = $true)]
        [string]$DeltaUrl
    )

    try {
        if ($DeltaUrl) {
            $GraphQuery = [System.UriBuilder]$DeltaUrl
        } else {
            $GraphQuery = [System.UriBuilder]('https://graph.microsoft.com/beta/{0}/delta' -f $Resource)
            $QueryParams = @{
                '$deltaToken' = 'latest'
            }
            $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)

            foreach ($key in $QueryParams.Keys) {
                if ($QueryParams[$key]) {
                    $ParamCollection.Add($key, $QueryParams[$key])
                }
            }

            foreach ($Item in ($Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
                if ($Item.Value -is [System.Boolean]) {
                    $Item.Value = $Item.Value.ToString().ToLower()
                }
                if ($Item.Value) {
                    $ParamCollection.Add($Item.Key, $Item.Value)
                }
            }
            $GraphQuery.Query = $ParamCollection.ToString()
        }
        
        $allResults = [System.Collections.ArrayList]::new()
        $nextUrl = $GraphQuery.ToString()
        $deltaLink = $null

        do {
            $response = New-GraphGetRequest -tenantid $TenantFilter -uri $nextUrl -ReturnRawResponse

            if ($response.Content) {
                $content = $response.Content
                if ($content -is [string]) {
                    $content = $content | ConvertFrom-Json
                }

                # Add results from this page
                if ($content.value) {
                    $allResults.AddRange($content.value)
                }

                # Check for next page or delta link
                $nextUrl = $content.'@odata.nextLink'
                $deltaLink = $content.'@odata.deltaLink'
            }
        } while ($nextUrl -and -not $deltaLink)

        # Return results with delta link for future queries
        $result = @{
            value              = $allResults.ToArray()
            '@odata.deltaLink' = $deltaLink
        }

        Write-Information "Delta Query completed for $Resource. Total items: $($allResults.Count)"

        # Always return full response with deltaLink
        return $result
    } catch {
        Write-Error "Failed to create Delta Query: $(Get-NormalizedError -Message $_.Exception.message)"
        Write-Warning $_.InvocationInfo.PositionMessage
    }
}
