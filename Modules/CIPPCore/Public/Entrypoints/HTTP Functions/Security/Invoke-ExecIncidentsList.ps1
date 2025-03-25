using namespace System.Net

Function Invoke-ExecIncidentsList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Incident.Read
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
            $incidents = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/incidents' -tenantid $TenantFilter -AsApp $true

            foreach ($incident in $incidents) {
                [PSCustomObject]@{
                    Tenant         = $TenantFilter
                    Id             = $incident.id
                    Status         = $incident.status
                    IncidentUrl    = $incident.incidentWebUrl
                    RedirectId     = $incident.redirectIncidentId
                    DisplayName    = $incident.displayName
                    Created        = $incident.createdDateTime
                    Updated        = $incident.lastUpdateDateTime
                    AssignedTo     = $incident.assignedTo
                    Classification = $incident.classification
                    Determination  = $incident.determination
                    Severity       = $incident.severity
                    Tags           = ($IncidentObj.tags -join ', ')
                    Comments       = $incident.comments
                }
            }
        } else {
            $Table = Get-CIPPTable -TableName cachealertsandincidents
            $PartitionKey = 'Incident'
            $Filter = "PartitionKey eq '$PartitionKey'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-30)
            $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
            $RunningQueue = Invoke-ListCippQueue | Where-Object { $_.Reference -eq $QueueReference -and $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
            # If a queue is running, we will not start a new one
            if ($RunningQueue) {
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Still loading data for all tenants. Please check back in a few more minutes'
                }
                [PSCustomObject]@{
                    Waiting = $true
                }
            } elseif (!$Rows -and !$RunningQueue) {
                # If no rows are found and no queue is running, we will start a new one
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'Incidents - All Tenants' -Link '/security/reports/incident-report?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'IncidentOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ExecIncidentsListAllTenants'
                    }
                    SkipLog          = $true
                }
                Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                [PSCustomObject]@{
                    Waiting = $true
                }
            } else {
                $incidents = $Rows
                foreach ($incident in $incidents) {
                    $IncidentObj = $incident.Incident | ConvertFrom-Json
                    [PSCustomObject]@{
                        Tenant         = $incident.Tenant
                        Id             = $IncidentObj.id
                        Status         = $IncidentObj.status
                        IncidentUrl    = $IncidentObj.incidentWebUrl
                        RedirectId     = $IncidentObj.redirectIncidentId
                        DisplayName    = $IncidentObj.displayName
                        Created        = $IncidentObj.createdDateTime
                        Updated        = $IncidentObj.lastUpdateDateTime
                        AssignedTo     = $IncidentObj.assignedTo
                        Classification = $IncidentObj.classification
                        Determination  = $IncidentObj.determination
                        Severity       = $IncidentObj.severity
                        Tags           = ($IncidentObj.tags -join ', ')
                        Comments       = @($IncidentObj.comments)
                    }
                }
            }
        }
    } catch {
        $StatusCode = [HttpStatusCode]::Forbidden
        $body = $_.Exception.message
    }
    if (!$body) {
        $StatusCode = [HttpStatusCode]::OK
        $body = [PSCustomObject]@{
            Results  = @($GraphRequest | Where-Object -Property id -NE $null | Sort-Object id -Descending)
            Metadata = $Metadata
        }
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })

}
