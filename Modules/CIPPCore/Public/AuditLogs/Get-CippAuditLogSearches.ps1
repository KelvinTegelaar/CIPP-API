function Get-CippAuditLogSearches {
    <#
    .SYNOPSIS
        Get the available audit log searches
    .DESCRIPTION
        Query the Graph API for available audit log searches.
    .PARAMETER TenantFilter
        The tenant to filter on.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter()]
        [switch]$ReadyToProcess
    )

    Measure-CippTask -TaskName 'GetAuditLogSearches' -EventName 'CIPP.AuditLogsProfile' -Script {
        $AuditLogSearchesTable = Get-CippTable -TableName 'AuditLogSearches'

        if ($ReadyToProcess.IsPresent) {
            Measure-CippTask -TaskName 'QueryReadyToProcess' -EventName 'CIPP.AuditLogsProfile' -Script {
                $15MinutesAgo = (Get-Date).AddMinutes(-15).ToUniversalTime()
                $1DayAgo = (Get-Date).AddDays(-1).ToUniversalTime()
                Get-CIPPAzDataTableEntity @AuditLogSearchesTable -Filter "PartitionKey eq 'Search' and Tenant eq '$TenantFilter'" | Where-Object {
                    $_.Timestamp -ge $1DayAgo -and (
                        $_.CippStatus -eq 'Pending' -or
                        ($_.CippStatus -eq 'Processing' -and $_.Timestamp -le $15MinutesAgo)
                    )
                } | Sort-Object Timestamp
            }
        } else {
            Measure-CippTask -TaskName 'QueryAllSearches' -EventName 'CIPP.AuditLogsProfile' -Script {
                $7DaysAgo = (Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                Get-CIPPAzDataTableEntity @AuditLogSearchesTable -Filter "Tenant eq '$TenantFilter' and Timestamp ge datetime'$7DaysAgo'"
            }
        }
    }

    Measure-CippTask -TaskName 'BuildBulkRequests' -EventName 'CIPP.AuditLogsProfile' -Script {
        $BulkRequests = foreach ($PendingQuery in $PendingQueries) {
            @{
                id     = $PendingQuery.RowKey
                url    = 'security/auditLog/queries/' + $PendingQuery.RowKey
                method = 'GET'
            }
        }
        $BulkRequests
    }

    if ($BulkRequests.Count -eq 0) {
        return @()
    }

    $Queries = Measure-CippTask -TaskName 'ExecuteBulkGraphRequests' -EventName 'CIPP.AuditLogsProfile' -Script {
        New-GraphBulkRequest -Requests @($BulkRequests) -AsApp $true -TenantId $TenantFilter | Select-Object -ExpandProperty body
    }

    if ($ReadyToProcess.IsPresent) {
        $Queries = Measure-CippTask -TaskName 'FilterSucceededQueries' -EventName 'CIPP.AuditLogsProfile' -Script {
            $Queries | Where-Object { $PendingQueries.RowKey -contains $_.id -and $_.status -eq 'succeeded' }
        }
    }

    return $Queries
}
