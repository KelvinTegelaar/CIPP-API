function Invoke-ListAuditLogSearches {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Alert.Read
    #>
    Param($Request, $TriggerMetadata)

    if ($Request.Query.TenantFilter) {
        switch ($Request.Query.Type) {
            'Searches' {
                $Results = Get-CippAuditLogSearches -TenantFilter $Request.Query.TenantFilter
                $Body = @{
                    Results  = @($Results)
                    Metadata = @{
                        TenantFilter  = $Request.Query.TenantFilter
                        TotalSearches = $Results.Count
                    }
                } | ConvertTo-Json -Depth 10 -Compress
            }
            'SearchResults' {
                try {
                    $Results = Get-CippAuditLogSearchResults -TenantFilter $Request.Query.TenantFilter -QueryId $Request.Query.SearchId
                } catch {
                    $Results = @{ Error = $_.Exception.Message }
                }
                $Body = @{
                    Results  = @($Results)
                    Metadata = @{
                        SearchId     = $Request.Query.SearchId
                        TenantFilter = $Request.Query.TenantFilter
                        TotalResults = $Results.Count
                    }
                } | ConvertTo-Json -Depth 10 -Compress
            }
            default {
                if ($Request.Query.Days) {
                    $Days = $Request.Query.Days
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
                        TenantFilter = $Request.Query.TenantFilter
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
