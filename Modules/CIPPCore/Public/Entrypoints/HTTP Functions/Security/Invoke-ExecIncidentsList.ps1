function Invoke-ExecIncidentsList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Incident.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $StartDate = $Request.Query.StartDate   # YYYYMMDD or null
    $EndDate = $Request.Query.EndDate     # YYYYMMDD or null

    # Build OData $filter parts for Graph API (single-tenant path)
    $GraphFilterParts = [System.Collections.Generic.List[string]]::new()
    if ($StartDate) {
        $GraphFilterParts.Add("createdDateTime ge $([datetime]::ParseExact($StartDate,'yyyyMMdd',$null).ToString('yyyy-MM-ddT00:00:00Z'))")
    }
    if ($EndDate) {
        $GraphFilterParts.Add("createdDateTime le $([datetime]::ParseExact($EndDate,'yyyyMMdd',$null).ToString('yyyy-MM-ddT23:59:59Z'))")
    }
    $GraphODataFilter = if ($GraphFilterParts.Count -gt 0) { '$filter=' + ($GraphFilterParts -join ' and ') } else { $null }

    try {
        $GraphRequest = if ($TenantFilter -ne 'AllTenants') {
            # Single tenant functionality
            $IncidentsUri = 'https://graph.microsoft.com/beta/security/incidents'
            if ($GraphODataFilter) { $IncidentsUri = "$IncidentsUri`?$GraphODataFilter" }
            $Incidents = New-GraphGetRequest -uri $IncidentsUri -tenantid $TenantFilter -AsApp $true

            foreach ($incident in $Incidents) {
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
                    Tags           = ($incident.tags -join ', ')
                    Comments       = $incident.comments
                }
            }
        } else {
            # AllTenants functionality
            $Table = Get-CIPPTable -TableName cachealertsandincidents
            $PartitionKey = 'Incident'
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
                $Queue = New-CippQueueEntry -Name 'Incidents - All Tenants' -Link '/security/reports/incident-report?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
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
                Start-CIPPOrchestrator -InputObject $InputObject | Out-Null
            } else {
                $Metadata = [PSCustomObject]@{
                    QueueId = $RunningQueue.RowKey ?? $null
                }
                $Incidents = $Rows
                foreach ($incident in $Incidents) {
                    if ($incident.Incident -and (Test-Json -Json $incident.Incident)) {
                        $IncidentObj = $incident.Incident | ConvertFrom-Json
                    } else {
                        continue
                    }
                    try {
                        $created = [datetime]::Parse($IncidentObj.createdDateTime)
                        if ($StartDate -and $created -lt [datetime]::ParseExact($StartDate, 'yyyyMMdd', $null)) { continue }
                        if ($EndDate -and $created -ge [datetime]::ParseExact($EndDate, 'yyyyMMdd', $null).AddDays(1)) { continue }
                    } catch {
                        continue
                    }
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
        $Body = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    if (!$Body) {
        $StatusCode = [HttpStatusCode]::OK
        $Body = [PSCustomObject]@{
            Results  = @($GraphRequest | Where-Object -Property id -NE $null | Sort-Object id -Descending)
            Metadata = $Metadata
        }
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
