function Invoke-ListAuditLogTest {
    <#
    .FUNCTIONALITY
    Entrypoint,AnyTenant

    .ROLE
    Tenant.Alert.Read
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $AuditLogQuery = @{
        TenantFilter = $Request.Query.TenantFilter
        SearchId     = $Request.Query.SearchId
    }
    try {
        $TestResults = Test-CIPPAuditLogRules @AuditLogQuery
    } catch {
        $Body = Get-CippException -Exception $_
        return @{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = $Body
        }
        return
    }
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
    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }

}
