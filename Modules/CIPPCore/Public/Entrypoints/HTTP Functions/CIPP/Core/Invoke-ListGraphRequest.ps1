
function Invoke-ListGraphRequest {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Message = 'Accessed this API | Endpoint: {0}' -f $Request.Query.Endpoint
    Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Debug'

    $CippLink = ([System.Uri]$TriggerMetadata.Headers.Referer).PathAndQuery

    $Parameters = @{}
    if ($Request.Query.'$filter') {
        $Parameters.'$filter' = $Request.Query.'$filter' -replace '%tenantid%', $env:TenantID
    }

    if (!$Request.Query.'$filter' -and $Request.Query.graphFilter) {
        $Parameters.'$filter' = $Request.Query.graphFilter -replace '%tenantid%', $env:TenantID
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

    if ($Request.Query.manualPagination) {
        $GraphRequestParams.NoPagination = [System.Boolean]$Request.Query.manualPagination
    }

    if ($Request.Query.nextLink) {
        $GraphRequestParams.nextLink = $Request.Query.nextLink
    }

    if ($Request.Query.CountOnly) {
        $GraphRequestParams.CountOnly = [System.Boolean]$Request.Query.CountOnly
    }

    if ($Request.Query.QueueNameOverride) {
        $GraphRequestParams.QueueNameOverride = [string]$Request.Query.QueueNameOverride
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

    if ($Request.Query.AsApp) {
        $GraphRequestParams.AsApp = $true
    }

    $Metadata = $GraphRequestParams

    try {
        $Results = Get-GraphRequestList @GraphRequestParams
        if ($Results.nextLink) {
            Write-Host "NextLink: $($Results.nextLink | Select-Object -Last 1)"
            if ($Request.Query.TenantFilter -ne 'AllTenants') {
                $Metadata['nextLink'] = $Results.nextLink | Select-Object -Last 1
            }
            #Results is an array of objects, so we need to remove the last object before returning
            $Results = $Results | Select-Object -First ($Results.Count - 1)
        }
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

        if ($Request.Headers.'x-ms-coldstart' -eq 1) {
            $Metadata.ColdStart = $true
        }

        $GraphRequestData = [PSCustomObject]@{
            Results  = @($Results)
            Metadata = $Metadata
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $GraphRequestData = "Graph Error: $(Get-NormalizedError $_.Exception.Message) - Endpoint: $($Request.Query.Endpoint)"
        if ($Request.Query.IgnoreErrors) { $StatusCode = [HttpStatusCode]::OK }
        else { $StatusCode = [HttpStatusCode]::BadRequest }
    }

    if ($request.Query.Sort) {
        $GraphRequestData.Results = $GraphRequestData.Results | Sort-Object -Property $request.Query.Sort
    }
    $Outputdata = $GraphRequestData | ConvertTo-Json -Depth 20 -Compress

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Outputdata
        })
}
