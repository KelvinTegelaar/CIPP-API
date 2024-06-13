function Invoke-ListAuditLogTest {
    <#
    .FUNCTIONALITY
    Entrypoint

    .ROLE
    Tenant.Alert.Read
    #>
    Param($Request, $TriggerMetadata)

    $AuditLogQuery = @{
        TenantFilter = $Request.Query.TenantFilter
        LogType      = $Request.Query.LogType
        ShowAll      = $true
    }
    $TestResults = Test-CIPPAuditLogRules @AuditLogQuery
    $Body = @{
        Results  = @($TestResults.DataToProcess)
        Metadata = @{
            TenantFilter = $AuditLogQuery.TenantFilter
            LogType      = $AuditLogQuery.LogType
            TotalLogs    = $TestResults.TotalLogs
            MatchedLogs  = $TestResults.MatchedLogs
            MatchedRules = $TestResults.MatchedRules
        }
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}