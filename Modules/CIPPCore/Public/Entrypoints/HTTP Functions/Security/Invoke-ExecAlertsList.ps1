using namespace System.Net

Function Invoke-ExecAlertsList {
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


    function New-FlatArray ([Array]$arr) {
        $arr | ForEach-Object {
            if ($_ -is 'Array') {
                New-FlatArray $_
            } else { $_ }
        }
    }
    try {
        # Interact with query parameters or the body of the request.
        $TenantFilter = $Request.Query.tenantFilter
        $GraphRequest = if ($TenantFilter -ne 'AllTenants') {
            $Alerts = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/alerts' -tenantid $TenantFilter
            $AlertsObj = foreach ($Alert in $Alerts) {
                @{
                    Tenant        = $TenantFilter
                    GUID          = $GUID
                    Id            = $Alert.Id
                    Title         = $Alert.Title
                    Category      = $Alert.category
                    EventDateTime = $Alert.eventDateTime
                    Severity      = $Alert.Severity
                    Status        = $Alert.Status
                    RawResult     = $($Alerts | Where-Object { $_.Id -eq $Alert.Id })
                    InvolvedUsers = $($Alerts | Where-Object { $_.Id -eq $Alert.Id }).userStates
                }
            }

            $DisplayableAlerts = New-FlatArray $AlertsObj | Where-Object { $null -ne $_.Id } | Sort-Object -Property EventDateTime -Descending
            if (!$DisplayableAlerts) {
                $DisplayableAlerts = @()
            }
            $Metadata = [PSCustomObject]@{}

            [PSCustomObject]@{
                NewAlertsCount             = $DisplayableAlerts | Where-Object { $_.Status -eq 'newAlert' } | Measure-Object | Select-Object -ExpandProperty Count
                InProgressAlertsCount      = $DisplayableAlerts | Where-Object { $_.Status -eq 'inProgress' } | Measure-Object | Select-Object -ExpandProperty Count
                SeverityHighAlertsCount    = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'high' } | Measure-Object | Select-Object -ExpandProperty Count
                SeverityMediumAlertsCount  = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'medium' } | Measure-Object | Select-Object -ExpandProperty Count
                SeverityLowAlertsCount     = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'low' } | Measure-Object | Select-Object -ExpandProperty Count
                SeverityInformationalCount = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'informational' } | Measure-Object | Select-Object -ExpandProperty Count
                MSResults                  = @($DisplayableAlerts)
            }
        } else {
            $Table = Get-CIPPTable -TableName cachealertsandincidents
            $PartitionKey = 'alert'
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
                $Queue = New-CippQueueEntry -Name 'Alerts List - All Tenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'AlertsOrchestrator'
                    QueueFunction    = [PSCustomObject]@{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ExecAlertsListAllTenants'
                    }
                    SkipLog          = $true
                } | ConvertTo-Json -Depth 10
                $InstanceId = Start-NewOrchestration -FunctionName CIPPOrchestrator -InputObject $InputObject
                [PSCustomObject]@{
                    Waiting    = $true
                    InstanceId = $InstanceId
                }
            } else {
                $Alerts = $Rows
                $AlertsObj = foreach ($Alert in $Alerts) {
                    $AlertInfo = $Alert.Alert | ConvertFrom-Json
                    @{
                        Tenant        = $Alert.Tenant
                        GUID          = $GUID
                        Id            = $AlertInfo.Id
                        Title         = $AlertInfo.Title
                        Category      = $AlertInfo.category
                        EventDateTime = $AlertInfo.eventDateTime
                        Severity      = $AlertInfo.Severity
                        Status        = $AlertInfo.Status
                        RawResult     = $AlertInfo
                        InvolvedUsers = $AlertInfo.userStates
                    }
                }
                $DisplayableAlerts = New-FlatArray $AlertsObj | Where-Object { $null -ne $_.Id } | Sort-Object -Property EventDateTime -Descending
                [PSCustomObject]@{
                    NewAlertsCount             = $DisplayableAlerts | Where-Object { $_.Status -eq 'newAlert' } | Measure-Object | Select-Object -ExpandProperty Count
                    InProgressAlertsCount      = $DisplayableAlerts | Where-Object { $_.Status -eq 'inProgress' } | Measure-Object | Select-Object -ExpandProperty Count
                    SeverityHighAlertsCount    = ($DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'high' } | Measure-Object | Select-Object -ExpandProperty Count)
                    SeverityMediumAlertsCount  = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'medium' } | Measure-Object | Select-Object -ExpandProperty Count
                    SeverityLowAlertsCount     = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'low' } | Measure-Object | Select-Object -ExpandProperty Count
                    SeverityInformationalCount = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'informational' } | Measure-Object | Select-Object -ExpandProperty Count
                    MSResults                  = ($DisplayableAlerts | Sort-Object -Property EventDateTime -Descending)
                }
            }
        }

    } catch {
        $StatusCode = [HttpStatusCode]::Forbidden
        $body = $_.Exception.message
    }
    if (!$body) {
        $StatusCode = [HttpStatusCode]::OK
        $body = @{
            Results  = $GraphRequest
            Metadata = $Metadata
        }
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
