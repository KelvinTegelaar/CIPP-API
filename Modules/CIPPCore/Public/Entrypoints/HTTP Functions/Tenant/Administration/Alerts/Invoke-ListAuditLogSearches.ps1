function Invoke-ListAuditLogSearches {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Alert.Read
    #>
    Param($Request, $TriggerMetadata)


    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with the query parameters
    $TenantFilter = $Request.Query.tenantFilter
    $SearchId = $Request.Query.SearchId
    $Days = $Request.Query.Days
    $Type = $Request.Query.Type


    if ($TenantFilter) {
        switch ($Type) {
            'Searches' {
                $Results = Get-CippAuditLogSearches -TenantFilter $TenantFilter
                $Body = @{
                    Results  = @($Results)
                    Metadata = @{
                        TenantFilter  = $TenantFilter
                        TotalSearches = $Results.Count
                    }
                } | ConvertTo-Json -Depth 10 -Compress
            }
            'SearchResults' {
                try {
                    $Results = Get-CippAuditLogSearchResults -TenantFilter $TenantFilter -QueryId $SearchId
                } catch {
                    $Results = @{ Error = $_.Exception.Message }
                }
                $Body = @{
                    Results  = @($Results)
                    Metadata = @{
                        SearchId     = $SearchId
                        TenantFilter = $TenantFilter
                        TotalResults = $Results.Count
                    }
                } | ConvertTo-Json -Depth 10 -Compress
            }
            default {
                if ($Days) {
                    $Days = $Days
                } else {
                    $Days = 1
                }
                $StartTime = (Get-Date).AddDays(-$Days).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

                $Table = Get-CIPPTable -TableName 'AuditLogSearches'
                $Results = Get-CIPPAzDataTableEntity @Table -Filter "StartTime ge datetime'$StartTime'" | ForEach-Object {
                    $Query = try { $_.Query | ConvertFrom-Json } catch { $_.Query }
                    $MatchedRules = try { $_.MatchedRules | ConvertFrom-Json } catch { $_.MatchedRules }
                    [PSCustomObject]@{
                        SearchId     = $_.RowKey
                        StartTime    = $_.StartTime.DateTime
                        EndTime      = $_.EndTime.DateTime
                        Query        = $Query
                        MatchedRules = $MatchedRules
                        TotalLogs    = $_.TotalLogs
                        MatchedLogs  = $_.MatchedLogs
                        CippStatus   = $_.CippStatus
                    }
                }

                $Body = @{
                    Results  = @($Results)
                    Metadata = @{
                        StartTime    = $StartTime
                        TenantFilter = $TenantFilter
                    }
                } | ConvertTo-Json -Depth 10 -Compress
            }
        }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Body
            })
    } else {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'TenantFilter is required'
            })
    }
}
