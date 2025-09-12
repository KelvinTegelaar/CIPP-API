using namespace System.Net

function Invoke-ListTransportRules {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.TransportRule.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $Results = if ($TenantFilter -ne 'AllTenants') {
            # Single tenant functionality
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-TransportRule'
        } else {
            # AllTenants functionality
            $Table = Get-CIPPTable -TableName CacheTransportRules
            $PartitionKey = 'TransportRule'
            $Filter = "PartitionKey eq '$PartitionKey'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-60)
            $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
            $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }

            # If a queue is running, we will not start a new one
            if ($RunningQueue) {
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Still loading transport rules for all tenants. Please check back in a few more minutes'
                    QueueId      = $RunningQueue.RowKey
                }
            } elseif (!$Rows -and !$RunningQueue) {
                # If no rows are found and no queue is running, we will start a new one
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'Transport Rules - All Tenants' -Link '/email/transport/list-rules?tenantFilter=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading transport rules for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'TransportRuleOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ListTransportRulesAllTenants'
                    }
                    SkipLog          = $true
                }
                Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress) | Out-Null
            } else {
                # Return cached data
                $Metadata = [PSCustomObject]@{
                    QueueId = $RunningQueue.RowKey ?? $null
                }
                $Rules = $Rows
                foreach ($rule in $Rules) {
                    $RuleObj = $rule.TransportRule | ConvertFrom-Json
                    $RuleObj | Add-Member -MemberType NoteProperty -Name Tenant -Value $rule.Tenant -Force
                    $RuleObj
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Body = $ErrorMessage
    }

    # If the body is not set by an error, we will set it here
    if (!$Body) {
        $Body = [PSCustomObject]@{
            Results  = @($Results)
            Metadata = $Metadata
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
