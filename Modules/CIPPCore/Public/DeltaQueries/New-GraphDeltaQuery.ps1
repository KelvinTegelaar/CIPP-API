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
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(DefaultParameterSetName = 'NewDeltaQuery')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'NewDeltaQuery')]
        [Parameter(Mandatory = $true, ParameterSetName = 'DeltaUrl')]
        $TenantFilter,

        [Parameter(ParameterSetName = 'NewDeltaQuery', Mandatory = $true)]
        [ValidateSet('users', 'groups', 'contacts', 'orgContact', 'devices', 'applications', 'servicePrincipals', 'directoryObjects', 'directoryRole', 'administrativeUnits', 'oAuth2PermissionGrant')]
        [string]$Resource,

        [Parameter(ParameterSetName = 'NewDeltaQuery', Mandatory = $false)]
        [hashtable]$Parameters = @{},

        [Parameter(ParameterSetName = 'DeltaUrl', Mandatory = $true)]
        [string]$DeltaUrl,

        [Parameter(Mandatory = $false, ParameterSetName = 'NewDeltaQuery')]
        [Parameter(Mandatory = $true, ParameterSetName = 'DeltaUrl')]
        [string]$PartitionKey
    )

    if ($TenantFilter -eq 'AllTenants' -or $TenantFilter.type -eq 'Group') {
        Write-Information 'Creating delta query for all tenants or tenant group.'
        if ($TenantFilter.type -eq 'group') {
            $Tenants = Expand-CIPPTenantGroups -TenantFilter $TenantFilter
        } else {
            $Tenants = Get-Tenants -IncludeErrors
        }

        if (!$PartitionKey) {
            $ParamJson = $Parameters | ConvertTo-Json -Depth 5 -Compress
            $PartitionKey = Get-StringHash -String ($Resource + $ParamJson)
        }
        # Prepare batch processing for all tenants
        $TenantBatch = $Tenants | ForEach-Object {
            [PSCustomObject]@{
                FunctionName = 'GraphDeltaQuery'
                TenantFilter = $_.defaultDomainName ?? $_.value
                Resource     = $Resource
                Parameters   = $Parameters
                PartitionKey = $PartitionKey
            }
        }

        $InputObject = @{
            Batch            = @($TenantBatch)
            OrchestratorName = 'ProcessDeltaQueries'
            SkipLog          = $true
        }
        Write-Information "Starting delta query orchestration for $($Tenants.Count) tenants."
        Write-Information "Orchestration Input: $($InputObject | ConvertTo-Json -Compress -Depth 5)"
        $Orchestration = Start-NewOrchestration -FunctionName CIPPOrchestrator -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)

    } else {
        $Table = Get-CIPPTable -TableName 'DeltaQueries'

        if ($Parameters -and $Resource) {
            $ParamJson = $Parameters | ConvertTo-Json -Depth 5
            $ResourceHash = Get-StringHash -String ($Resource + $ParamJson)

            $DeltaQuery = @{
                PartitionKey = $PartitionKey ?? $ResourceHash
                RowKey       = $TenantFilter
                Resource     = $Resource
                Parameters   = [string]($Parameters | ConvertTo-Json -Depth 5 -Compress)
                DeltaUrl     = $DeltaUrl
            }
        } elseif ($PartitionKey) {
            $DeltaQuery = Get-AzDataTableEntity @Table -Filter "PartitionKey eq '$PartitionKey' and RowKey eq '$TenantFilter'"
        }

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

            $DeltaError = $false
            do {
                try {
                    $response = New-GraphGetRequest -tenantid $TenantFilter -uri $nextUrl -ReturnRawResponse -extraHeaders @{ Prefer = 'return=minimal' } -ErrorAction Stop
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
                } catch {
                    Write-Error "Error during Graph Delta Query request for tenant '$TenantFilter': $(Get-NormalizedError -Message $_.Exception.message)"
                    $DeltaError = $true
                }
            } while ($nextUrl -and -not $deltaLink -and -not $DeltaError)

            if ($DeltaError) {
                throw "Delta Query failed for tenant '$TenantFilter'."
            }
            $DeltaQuery.RowKey = $TenantFilter
            $DeltaQuery.DeltaUrl = $deltaLink

            # Return results with delta link for future queries
            $result = @{
                value              = $allResults.ToArray()
                '@odata.deltaLink' = $deltaLink
                PartitionKey       = $PartitionKey
            }
            # Save link to table
            Add-CIPPAzDataTableEntity @Table -Entity $DeltaQuery -Force

            Write-Information "Delta Query created for $($DeltaQuery.Resource). Total items: $($allResults.Count)"

            # Always return full response with deltaLink
            return $result
        } catch {
            Write-Error "Failed to create Delta Query: $(Get-NormalizedError -Message $_.Exception.message)"
            Write-Warning $_.InvocationInfo.PositionMessage
        }
    }
}
