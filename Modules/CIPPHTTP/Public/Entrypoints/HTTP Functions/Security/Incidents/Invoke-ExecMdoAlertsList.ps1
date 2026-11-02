function Invoke-ExecMDOAlertsList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Alert.Read
    .DESCRIPTION
        Lists Microsoft Defender for Office 365 and Defender for Endpoint alerts for a tenant, filtered to those service sources. tenantFilter=AllTenants reads the cached alert table rather than querying each tenant live.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $ServiceFilter = "serviceSource eq 'microsoftDefenderForOffice365' or serviceSource eq 'microsoftDefenderForEndpoint'"

    try {
        $Metadata = [PSCustomObject]@{}
        $GraphRequest = if ($TenantFilter -ne 'AllTenants') {
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/security/alerts_v2?`$filter=$ServiceFilter" -tenantid $TenantFilter
        } else {
            $CacheStatus = @{}
            $Cached = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'security/alerts_v2' -Parameters @{ '$filter' = $ServiceFilter } -CacheStatus $CacheStatus
            if ($Cached.Queued -eq $true) {
                $Metadata = [PSCustomObject]@{ QueueMessage = $Cached.QueueMessage; QueueId = $Cached.QueueId }
            } else {
                $Metadata = [PSCustomObject]@{ QueueId = $CacheStatus.QueueId; CachedTenants = $CacheStatus.CachedTenants; ExpectedTenants = $CacheStatus.ExpectedTenants }
                $Cached
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        $Body = [PSCustomObject]@{
            Results  = @($GraphRequest)
            Metadata = $Metadata
        }
    } catch {
        $Body = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
