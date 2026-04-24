
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

    if ($Request.Query.expand) {
        $Parameters.'expand' = $Request.Query.expand
    }

    if ($Request.Query.'$top') {
        $Parameters.'$top' = $Request.Query.'$top'
    }

    if ($Request.Query.'$count') {
        $Parameters.'$count' = ([string]([System.Convert]::ToBoolean($Request.Query.'$count'))).ToLower()
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
        $GraphRequestParams.NoPagination = [System.Convert]::ToBoolean($Request.Query.NoPagination)
    }

    if ($Request.Query.manualPagination) {
        $GraphRequestParams.ManualPagination = [System.Convert]::ToBoolean($Request.Query.manualPagination)
    }

    if ($Request.Query.nextLink) {
        $GraphRequestParams.nextLink = $Request.Query.nextLink
    }

    if ($Request.Query.CountOnly) {
        $GraphRequestParams.CountOnly = [System.Convert]::ToBoolean($Request.Query.CountOnly)
    }

    if ($Request.Query.QueueNameOverride) {
        $GraphRequestParams.QueueNameOverride = [string]$Request.Query.QueueNameOverride
    }

    if ($Request.Query.ReverseTenantLookup) {
        $GraphRequestParams.ReverseTenantLookup = [System.Convert]::ToBoolean($Request.Query.ReverseTenantLookup)
    }

    if ($Request.Query.ReverseTenantLookupProperty) {
        $GraphRequestParams.ReverseTenantLookupProperty = $Request.Query.ReverseTenantLookupProperty
    }

    if ($Request.Query.SkipCache) {
        $GraphRequestParams.SkipCache = [System.Convert]::ToBoolean($Request.Query.SkipCache)
    }

    if ($Request.Query.ListProperties) {
        $GraphRequestParams.NoPagination = $true
        $GraphRequestParams.Parameters.'$select' = ''
        if ($Request.Query.TenantFilter -eq 'AllTenants') {
            $GraphRequestParams.TenantFilter = (Get-Tenants | Select-Object -First 1).customerId
        }
    }

    if ($Request.Query.AsApp) {
        $GraphRequestParams.AsApp = [System.Convert]::ToBoolean($Request.Query.AsApp)
    }

    $Metadata = $GraphRequestParams

    # Use raw JSON passthrough for AllTenants cached results when no post-processing is needed.
    $UseRawJson = $Request.Query.TenantFilter -eq 'AllTenants' -and
                  -not $Request.Query.ListProperties -and
                  -not $Request.Query.Sort -and
                  -not $Request.Query.QueueId

    try {
        if ($UseRawJson) {
            $GraphRequestParams.RawJsonArray = $true
        }
        $Results = Get-GraphRequestList @GraphRequestParams

        if ($script:LastGraphResponseHeaders) {
            $Metadata.GraphHeaders = $script:LastGraphResponseHeaders
        }

        # RawJsonArray returns a JSON string directly — skip object-level processing
        if ($UseRawJson -and $Results -is [string] -and $Results.StartsWith('[')) {
            if ($Request.Headers.'x-ms-coldstart' -eq 1) {
                $Metadata.ColdStart = $true
            }
            $MetadataJson = ConvertTo-Json -InputObject $Metadata -Depth 5 -Compress
            $GraphRequestData = '{"Results":' + $Results + ',"Metadata":' + $MetadataJson + '}'
            $StatusCode = [HttpStatusCode]::OK

            return ([HttpResponseContext]@{
                    StatusCode  = $StatusCode
                    ContentType = 'application/json'
                    Body        = $GraphRequestData
                })
        }

        if ($Results | Where-Object { $_.PSObject.Properties.Name -contains 'nextLink' }) {
            $NextLink = $Results.nextLink | Where-Object { $_ } | Select-Object -Last 1
            if ($NextLink -and $Request.Query.TenantFilter -ne 'AllTenants') {
                Write-Host "NextLink: $NextLink"
                $Metadata['nextLink'] = $NextLink
            }
            # Remove nextLink trailing object only if it’s the last item
            $Results = $Results | Where-Object { $_.PSObject.Properties.Name -notcontains 'nextLink' }
        }
        if ($Request.Query.ListProperties) {
            $Columns = ($Results | Select-Object -First 1).PSObject.Properties.Name
            $Results = $Columns | Where-Object { @('Tenant', 'CippStatus') -notcontains $_ }
        } else {
            if ($Results.Queued -eq $true) {
                $Metadata.Queued = $Results.Queued
                $Metadata.QueueMessage = $Results.QueueMessage
                $Metadata.QueueId = $Results.QueueId
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

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $GraphRequestData
        })
}
