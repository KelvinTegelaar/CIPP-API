function Invoke-ExecIncidentsList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Incident.Read
    .DESCRIPTION
        Lists Microsoft 365 Defender security incidents for a tenant, optionally bounded by StartDate and EndDate (both YYYYMMDD). tenantFilter=AllTenants reads the cached incident table rather than querying each tenant live.
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
        $Metadata = [PSCustomObject]@{}
        $Incidents = if ($TenantFilter -ne 'AllTenants') {
            $IncidentsUri = 'https://graph.microsoft.com/beta/security/incidents'
            if ($GraphODataFilter) { $IncidentsUri = "$IncidentsUri`?$GraphODataFilter" }
            New-GraphGetRequest -uri $IncidentsUri -tenantid $TenantFilter -AsApp $true
        } else {
            $CacheStatus = @{}
            $Cached = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'security/incidents' -AsApp $true -CacheStatus $CacheStatus
            if ($Cached.Queued -eq $true) {
                $Metadata = [PSCustomObject]@{ QueueMessage = $Cached.QueueMessage; QueueId = $Cached.QueueId }
            } else {
                $Metadata = [PSCustomObject]@{ QueueId = $CacheStatus.QueueId; CachedTenants = $CacheStatus.CachedTenants; ExpectedTenants = $CacheStatus.ExpectedTenants }
                # The cache holds every incident, so the date range is applied here
                $From = if ($StartDate) { [datetime]::ParseExact($StartDate, 'yyyyMMdd', $null) }
                $Until = if ($EndDate) { [datetime]::ParseExact($EndDate, 'yyyyMMdd', $null).AddDays(1) }
                foreach ($Incident in $Cached) {
                    $Created = $Incident.createdDateTime -as [datetime]
                    if (($From -and $Created -lt $From) -or ($Until -and $Created -ge $Until)) { continue }
                    $Incident
                }
            }
        }

        $GraphRequest = foreach ($incident in $Incidents) {
            if ($null -eq $incident.id) { continue }
            [PSCustomObject]@{
                Tenant         = $incident.Tenant ?? $TenantFilter
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
                Comments       = @($incident.comments)
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        $Body = [PSCustomObject]@{
            Results  = @($GraphRequest | Sort-Object id -Descending)
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
