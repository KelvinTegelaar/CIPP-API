function Invoke-ListAuditLogTest {
    <#
    .FUNCTIONALITY
    Entrypoint,AnyTenant

    .ROLE
    Tenant.Alert.Read
    .DESCRIPTION
        Tests audit log webhook rules against a specific search to validate rule matching and alert triggering.
    #>
    Param($Request, $TriggerMetadata)
    $AuditLogQuery = @{
        TenantFilter = $Request.Query.TenantFilter
        SearchId     = $Request.Query.SearchId
    }

    # AnyTenant: enforce tenant scope here; Get-Tenants is narrowed to the caller's allowed tenants
    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants' -and -not ($AuditLogQuery.TenantFilter -and (Get-Tenants -TenantFilter $AuditLogQuery.TenantFilter))) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = @{ Results = 'Access to this tenant is not allowed' }
            })
    }

    try {
        $TestResults = Test-CIPPAuditLogRules @AuditLogQuery
    } catch {
        $Body = Get-CippException -Exception $_
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = $Body
            })
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
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
