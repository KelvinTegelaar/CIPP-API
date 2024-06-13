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
    $Results = Test-CIPPAuditLogRules @AuditLogQuery
    $Body = @{
        Results = @($Results)
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}