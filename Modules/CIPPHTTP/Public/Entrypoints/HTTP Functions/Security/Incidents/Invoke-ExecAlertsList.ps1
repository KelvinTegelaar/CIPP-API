function Invoke-ExecAlertsList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Alert.Read
    .DESCRIPTION
        Lists Microsoft 365 Defender security alerts for a tenant. tenantFilter=AllTenants reads the cached alert table instead of querying each tenant live, so those results are as fresh as the last cache run.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    try {
        $TenantFilter = $Request.Query.tenantFilter
        $Metadata = [PSCustomObject]@{}
        $Alerts = if ($TenantFilter -eq 'AllTenants') {
            $CacheStatus = @{}
            $Cached = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'security/alerts_v2' -CacheStatus $CacheStatus
            if ($Cached.Queued -eq $true) {
                $Metadata = [PSCustomObject]@{ QueueMessage = $Cached.QueueMessage; QueueId = $Cached.QueueId }
            } else {
                $Metadata = [PSCustomObject]@{ QueueId = $CacheStatus.QueueId; CachedTenants = $CacheStatus.CachedTenants; ExpectedTenants = $CacheStatus.ExpectedTenants }
                $Cached
            }
        } else {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/alerts_v2' -tenantid $TenantFilter
        }

        $DisplayableAlerts = @(foreach ($Alert in $Alerts) {
                if ($null -eq $Alert.id) { continue }
                @{
                    Tenant        = $Alert.Tenant ?? $TenantFilter
                    GUID          = (New-Guid).Guid
                    Id            = $Alert.id
                    Title         = $Alert.title
                    Category      = $Alert.category
                    EventDateTime = $Alert.firstActivityDateTime
                    Severity      = $Alert.severity
                    Status        = $Alert.status
                    RawResult     = $Alert
                    InvolvedUsers = @($Alert.evidence | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.security.userEvidence' }).userAccount
                }
            }) | Sort-Object -Property EventDateTime -Descending
        $Open = @($DisplayableAlerts | Where-Object { $_.Status -in 'new', 'inProgress' })

        $GraphRequest = [PSCustomObject]@{
            NewAlertsCount             = @($DisplayableAlerts | Where-Object { $_.Status -eq 'new' }).Count
            InProgressAlertsCount      = @($DisplayableAlerts | Where-Object { $_.Status -eq 'inProgress' }).Count
            SeverityHighAlertsCount    = @($Open | Where-Object { $_.Severity -eq 'high' }).Count
            SeverityMediumAlertsCount  = @($Open | Where-Object { $_.Severity -eq 'medium' }).Count
            SeverityLowAlertsCount     = @($Open | Where-Object { $_.Severity -eq 'low' }).Count
            SeverityInformationalCount = @($Open | Where-Object { $_.Severity -eq 'informational' }).Count
            MSResults                  = @($DisplayableAlerts)
        }
        $StatusCode = [HttpStatusCode]::OK
        $Body = @{
            Results  = $GraphRequest
            Metadata = $Metadata
        }
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = $_.Exception.Message
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
