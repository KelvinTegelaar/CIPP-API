
function Invoke-ListGraphRequest {
    <#
    .FUNCTIONALITY
    Entrypoint

    .ROLE
    Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    $Message = 'Accessed this API | Endpoint: {0}' -f $Request.Query.Endpoint
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message $Message -Sev 'Debug'

    $CippLink = ([System.Uri]$TriggerMetadata.Headers.referer).PathAndQuery

    $Parameters = @{}
    if ($Request.Query.'$filter') {
        $Parameters.'$filter' = $Request.Query.'$filter'
    }

    if (!$Request.Query.'$filter' -and $Request.Query.graphFilter) {
        $Parameters.'$filter' = $Request.Query.graphFilter
    }

    if ($Request.Query.'$select') {
        $Parameters.'$select' = $Request.Query.'$select'
    }

    if ($Request.Query.'$expand') {
        $Parameters.'$expand' = $Request.Query.'$expand'
    }

    if ($Request.Query.'$top') {
        $Parameters.'$top' = $Request.Query.'$top'
    }

    if ($Request.Query.'$count') {
        $Parameters.'$count' = ([string]([System.Boolean]$Request.Query.'$count')).ToLower()
    }

    if ($Request.Query.'$orderby') {
        $Parameters.'$orderby' = $Request.Query.'$orderby'
    }

    if ($Request.Query.'$search') {
        $Parameters.'$search' = $Request.Query.'$search'
    }

    if ($Request.Query.'$format') {
        $Parameters.'$format' = $Request.Query.'$format'
    }

    $GraphRequestParams = @{
        Endpoint   = $Request.Query.Endpoint
        Parameters = $Parameters
        CippLink   = $CippLink
    }

    if ($Request.Query.TenantFilter) {
        $GraphRequestParams.TenantFilter = $Request.Query.TenantFilter
    }

    if ($Request.Query.QueueId) {
        $GraphRequestParams.QueueId = $Request.Query.QueueId
    }

    if ($Request.Query.Version) {
        $GraphRequestParams.Version = $Request.Query.Version
    }

    if ($Request.Query.NoPagination) {
        $GraphRequestParams.NoPagination = [System.Boolean]$Request.Query.NoPagination
    }

    if ($Request.Query.CountOnly) {
        $GraphRequestParams.CountOnly = [System.Boolean]$Request.Query.CountOnly
    }

    if ($Request.Query.QueueNameOverride) {
        $GraphRequestParams.QueueNameOverride = [System.Boolean]$Request.Query.QueueNameOverride
    }

    if ($Request.Query.ReverseTenantLookup) {
        $GraphRequestParams.ReverseTenantLookup = [System.Boolean]$Request.Query.ReverseTenantLookup
    }

    if ($Request.Query.ReverseTenantLookupProperty) {
        $GraphRequestParams.ReverseTenantLookupProperty = $Request.Query.ReverseTenantLookupProperty
    }

    if ($Request.Query.SkipCache) {
        $GraphRequestParams.SkipCache = [System.Boolean]$Request.Query.SkipCache
    }

    if ($Request.Query.ListProperties) {
        $GraphRequestParams.NoPagination = $true
        $GraphRequestParams.Parameters.'$select' = ''
        if ($Request.Query.TenantFilter -eq 'AllTenants') {
            $GraphRequestParams.TenantFilter = (Get-Tenants | Select-Object -First 1).customerId
        }
    }

    Write-Host ($GraphRequestParams | ConvertTo-Json)

    $Metadata = $GraphRequestParams

    try {
        $Results = Get-GraphRequestList @GraphRequestParams

        if ($Request.Query.ListProperties) {
            $Columns = ($Results | Select-Object -First 1).PSObject.Properties.Name
            $Results = $Columns | Where-Object { @('Tenant', 'CippStatus') -notcontains $_ }
        } else {
            if ($Results.Queued -eq $true) {
                $Metadata.Queued = $Results.Queued
                $Metadata.QueueMessage = $Results.QueueMessage
                $Metadata.QueuedId = $Results.QueueId
                $Results = @()
            }
        }
        $GraphRequestData = [PSCustomObject]@{
            Results  = @($Results)
            Metadata = $Metadata
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $GraphRequestData = "Graph Error: $($_.Exception.Message) - Endpoint: $($Request.Query.Endpoint)"
        if ($Request.Query.IgnoreErrors) { $StatusCode = [HttpStatusCode]::OK }
        else { $StatusCode = [HttpStatusCode]::BadRequest }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $GraphRequestData | ConvertTo-Json -Depth 20 -Compress
        })
}