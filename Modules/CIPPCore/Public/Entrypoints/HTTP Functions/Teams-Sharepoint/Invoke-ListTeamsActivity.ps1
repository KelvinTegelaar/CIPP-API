function Invoke-ListTeamsActivity {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Activity.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $type = $request.Query.Type

    if ($TenantFilter -eq 'AllTenants') {
        # AllTenants functionality
        $Table = Get-CIPPTable -TableName 'cacheTeamsActivity'
        $PartitionKey = 'TeamsActivity'
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
            $Queue = New-CippQueueEntry -Name 'Teams Activity - All Tenants' -Link '/teams-share/teams/teams-activity?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
            $Metadata = [PSCustomObject]@{
                QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                QueueId      = $Queue.RowKey
            }
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'TeamsActivityOrchestrator'
                QueueFunction    = @{
                    FunctionName = 'GetTenants'
                    QueueId      = $Queue.RowKey
                    TenantParams = @{
                        IncludeErrors = $true
                    }
                    DurableName  = 'ListTeamsActivityAllTenants'
                }
                SkipLog          = $true
            }
            Start-CIPPOrchestrator -InputObject $InputObject | Out-Null
        } else {
            $Metadata = [PSCustomObject]@{
                QueueId = $RunningQueue.RowKey ?? $null
            }
            $GraphRequest = foreach ($policy in $Rows) {
                ($policy.Policy | ConvertFrom-Json)
            }
        }
    } else {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/get$($type)Detail(period='D30')" -tenantid $TenantFilter | ConvertFrom-Csv | Select-Object @{ Name = 'UPN'; Expression = { $_.'User Principal Name' } },
        @{ Name = 'LastActive'; Expression = { $_.'Last Activity Date' } },
        @{ Name = 'TeamsChat'; Expression = { $_.'Team Chat Message Count' } },
        @{ Name = 'CallCount'; Expression = { $_.'Call Count' } },
        @{ Name = 'MeetingCount'; Expression = { $_.'Meeting Count' } }
    }

    $Body = [PSCustomObject]@{
        Results  = @($GraphRequest | Where-Object { $null -ne $_.UPN })
        Metadata = $Metadata
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
