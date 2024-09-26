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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    function New-FlatArray ([Array]$arr) {
        $arr | ForEach-Object {
            if ($_ -is 'Array') {
                New-FlatArray $_
            } else { $_ }
        }
    }
    try {
        # Interact with query parameters or the body of the request.
        $TenantFilter = $Request.Query.TenantFilter
        $GraphRequest = if ($TenantFilter -ne 'AllTenants') {
            $Alerts = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/alerts' -tenantid $TenantFilter
            $AlertsObj = foreach ($Alert In $alerts) {
                @{
                    Tenant        = $TenantFilter
                    GUID          = $GUID
                    Id            = $alert.Id
                    Title         = $alert.Title
                    Category      = $alert.category
                    EventDateTime = $alert.eventDateTime
                    Severity      = $alert.Severity
                    Status        = $alert.Status
                    RawResult     = $($Alerts | Where-Object { $_.Id -eq $alert.Id })
                    InvolvedUsers = $($Alerts | Where-Object { $_.Id -eq $alert.Id }).userStates
                }
            }

            $DisplayableAlerts = New-FlatArray $AlertsObj | Where-Object { $_.Id -ne $null } | Sort-Object -Property EventDateTime -Descending

            [PSCustomObject]@{
                NewAlertsCount             = $DisplayableAlerts | Where-Object { $_.Status -eq 'newAlert' } | Measure-Object | Select-Object -ExpandProperty Count
                InProgressAlertsCount      = $DisplayableAlerts | Where-Object { $_.Status -eq 'inProgress' } | Measure-Object | Select-Object -ExpandProperty Count
                SeverityHighAlertsCount    = ($DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'high' } | Measure-Object | Select-Object -ExpandProperty Count)
                SeverityMediumAlertsCount  = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'medium' } | Measure-Object | Select-Object -ExpandProperty Count
                SeverityLowAlertsCount     = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'low' } | Measure-Object | Select-Object -ExpandProperty Count
                SeverityInformationalCount = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'informational' } | Measure-Object | Select-Object -ExpandProperty Count
                MSResults                  = $DisplayableAlerts
            }
        } else {
            $Table = Get-CIPPTable -TableName cachealertsandincidents
            $Filter = "PartitionKey eq 'alert'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-10)
            if (!$Rows) {
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'Alerts List - All Tenants' -TotalTasks ($TenantList | Measure-Object).Count
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'AlertsList'
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
                $AlertsObj = foreach ($Alert in $alerts) {
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
                $DisplayableAlerts = New-FlatArray $AlertsObj | Where-Object { $_.Id -ne $null } | Sort-Object -Property EventDateTime -Descending
                [PSCustomObject]@{
                    NewAlertsCount             = $DisplayableAlerts | Where-Object { $_.Status -eq 'newAlert' } | Measure-Object | Select-Object -ExpandProperty Count
                    InProgressAlertsCount      = $DisplayableAlerts | Where-Object { $_.Status -eq 'inProgress' } | Measure-Object | Select-Object -ExpandProperty Count
                    SeverityHighAlertsCount    = ($DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'high' } | Measure-Object | Select-Object -ExpandProperty Count)
                    SeverityMediumAlertsCount  = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'medium' } | Measure-Object | Select-Object -ExpandProperty Count
                    SeverityLowAlertsCount     = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'low' } | Measure-Object | Select-Object -ExpandProperty Count
                    SeverityInformationalCount = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'informational' } | Measure-Object | Select-Object -ExpandProperty Count
                    MSResults                  = $DisplayableAlerts
                }
            }
        }

    } catch {
        $StatusCode = [HttpStatusCode]::Forbidden
        $body = $_.Exception.message
    }
    if (!$body) {
        $StatusCode = [HttpStatusCode]::OK
        $body = $GraphRequest
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
