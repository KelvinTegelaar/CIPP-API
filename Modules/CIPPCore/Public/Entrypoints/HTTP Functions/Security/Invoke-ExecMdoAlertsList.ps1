using namespace System.Net

function Invoke-ExecMDOAlertsList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Alert.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $GraphRequest = if ($TenantFilter -ne 'AllTenants') {
            # Single tenant functionality
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/security/alerts_v2?`$filter=serviceSource eq 'microsoftDefenderForOffice365'" -tenantid $TenantFilter
        } else {
            # AllTenants functionality
            $Table = Get-CIPPTable -TableName cachealertsandincidents
            $PartitionKey = 'MdoAlert'
            $Filter = "PartitionKey eq '$PartitionKey'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-30)
            $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
            $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
            # If a queue is running, we will not start a new one
            if ($RunningQueue) {
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Still loading data for all tenants. Please check back in a few more minutes'
                    QueueId      = $RunningQueue.RowKey
                }
            } elseif (!$Rows -and !$RunningQueue) {
                # If no rows are found and no queue is running, we will start a new one
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'MDO Alerts - All Tenants' -Link '/security/reports/mdo-alerts?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'MdoAlertsOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ExecMdoAlertsListAllTenants'
                    }
                    SkipLog          = $true
                }
                Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress) | Out-Null
            } else {
                $Metadata = [PSCustomObject]@{
                    QueueId = $RunningQueue.RowKey ?? $null
                }
                $Alerts = $Rows
                foreach ($alert in $Alerts) {
                    ConvertFrom-Json -InputObject $alert.MdoAlert -Depth 10
                }
            }
        }
    } catch {
        $Body = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    if (!$Body) {
        $StatusCode = [HttpStatusCode]::OK
        $Body = [PSCustomObject]@{
            Results  = @($GraphRequest)
            Metadata = $Metadata
        }
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
