function Invoke-ListAssignmentFilters {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Get the tenant filter
    $TenantFilter = $Request.Query.tenantFilter
    $FilterId = $Request.Query.filterId

    if ($TenantFilter -eq 'AllTenants') {
        # AllTenants functionality
        $Table = Get-CIPPTable -TableName 'cacheAssignmentFilters'
        $PartitionKey = 'AssignmentFilter'
        $Filter = "PartitionKey eq '$PartitionKey'"
        $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-60)
        $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
        $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
        if ($RunningQueue) {
            $Metadata = [PSCustomObject]@{
                QueueMessage = 'Still loading data for all tenants. Please check back in a few more minutes'
                QueueId      = $RunningQueue.RowKey
            }
        } elseif (!$Rows -and !$RunningQueue) {
            $TenantList = Get-Tenants -IncludeErrors
            $Queue = New-CippQueueEntry -Name 'Assignment Filters - All Tenants' -Link '/endpoint/MEM/assignment-filters?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
            $Metadata = [PSCustomObject]@{
                QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                QueueId      = $Queue.RowKey
            }
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'AssignmentFiltersOrchestrator'
                QueueFunction    = @{
                    FunctionName = 'GetTenants'
                    QueueId      = $Queue.RowKey
                    TenantParams = @{
                        IncludeErrors = $true
                    }
                    DurableName  = 'ListAssignmentFiltersAllTenants'
                }
                SkipLog          = $true
            }
            Start-CIPPOrchestrator -InputObject $InputObject | Out-Null
        } else {
            $Metadata = [PSCustomObject]@{
                QueueId = $RunningQueue.RowKey ?? $null
            }
            $AssignmentFilters = foreach ($policy in $Rows) {
                ($policy.Policy | ConvertFrom-Json)
            }
        }
        $Body = [PSCustomObject]@{
            Results  = @($AssignmentFilters)
            Metadata = $Metadata
        }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Body
            })
    }

    try {
        if ($FilterId) {
            # Get specific filter
            $AssignmentFilters = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$($FilterId)" -tenantid $TenantFilter
        } else {
            # Get all filters
            $AssignmentFilters = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -tenantid $TenantFilter
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to retrieve assignment filters: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $AssignmentFilters = @()
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = [PSCustomObject]@{
                Results  = @($AssignmentFilters | Where-Object -Property id -NE $null)
                Metadata = $null
            }
        })
}
