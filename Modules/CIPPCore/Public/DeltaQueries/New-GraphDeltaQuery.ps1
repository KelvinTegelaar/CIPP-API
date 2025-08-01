function New-GraphDeltaQuery {
    <#
    .SYNOPSIS
        Creates a new Graph Delta Query.
    .DESCRIPTION
        This function creates a new Graph Delta Query to track changes in a specified resource.
    .PARAMETER Resource
        The resource to track changes for (e.g., 'users', 'groups').
    .PARAMETER TenantFilter
        The tenant to filter the query on.
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

        #Write-Information "Creating Delta Query for $Resource with parameters: $($GraphQuery.Query)"
        $response = New-GraphGetRequest -tenantid $TenantFilter -uri $GraphQuery.ToString() -ReturnRawResponse
        Write-Information "Delta Query created successfully for $Resource. Response: $($response | ConvertTo-Json -Depth 5)"
        return $response.Content
    } catch {
        Write-Error "Failed to create Delta Query: $(Get-NormalizedError -Message $_.Exception.message)"
        Write-Warning $_.InvocationInfo.PositionMessage
    }
}
