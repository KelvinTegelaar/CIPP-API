function Invoke-ListConnectionFilter {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.ConnectionFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $request.Query.tenantFilter

    try {
        if ($TenantFilter -eq 'AllTenants') {
            # AllTenants functionality
            $Table = Get-CIPPTable -TableName CacheConnectionFilter
            $PartitionKey = 'ConnectionFilter'
            $Filter = "PartitionKey eq '$PartitionKey'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-60)
            $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
            $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
            if ($RunningQueue) {
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Still loading connection filters for all tenants. Please check back in a few more minutes'
                    QueueId      = $RunningQueue.RowKey
                }
            } elseif (!$Rows -and !$RunningQueue) {
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'Connection Filters - All Tenants' -Link '/email/spamfilter/list-connectionfilter?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading connection filters for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'ConnectionFilterOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ListConnectionFilterAllTenants'
                    }
                    SkipLog          = $true
                }
                Start-CIPPOrchestrator -InputObject $InputObject | Out-Null
            } else {
                $Metadata = [PSCustomObject]@{
                    QueueId = $RunningQueue.RowKey ?? $null
                }
                $Policies = foreach ($policy in $Rows) {
                    ($policy.Policy | ConvertFrom-Json)
                }
            }
        } else {
            $Policies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-HostedConnectionFilterPolicy' | Select-Object * -ExcludeProperty *odata*, *data.type*
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Policies = $ErrorMessage
    }

    $Body = [PSCustomObject]@{
        Results  = @($Policies | Where-Object { $_.Id -ne $null })
        Metadata = $Metadata
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
