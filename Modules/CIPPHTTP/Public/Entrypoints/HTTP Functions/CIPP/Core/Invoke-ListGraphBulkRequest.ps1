function Invoke-ListGraphBulkRequest {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Executes multiple Microsoft Graph API requests in a single batch call for a given tenant. Accepts an array of request objects in the body.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Body.tenantFilter
    $AsApp = $Request.Body.asApp
    $Requests = $Request.Body.requests
    $NoPaginateIds = $Request.Body.noPaginateIds

    $GraphRequestParams = @{
        tenantid      = $TenantFilter
        Requests      = @()
        NoPaginateIds = $NoPaginateIds ?? @()
    }

    if ($AsApp) {
        $GraphRequestParams.asapp = $AsApp
    }

    $BulkRequests = foreach ($GraphRequest in $Requests) {
        if ($GraphRequest.method -eq 'GET') {
            @{
                id     = $GraphRequest.id
                url    = $GraphRequest.url
                method = $GraphRequest.method
            }
        }
    }

    if ($BulkRequests) {
        $GraphRequestParams.Requests = @($BulkRequests)
        try {
            $Body = New-GraphBulkRequest @GraphRequestParams
            $Results = @{
                StatusCode = [System.Net.HttpStatusCode]::OK
                Body       = $Body
            }
        } catch {
            $Results = @{
                StatusCode = [System.Net.HttpStatusCode]::BadRequest
                Body       = $_.Exception.Message
            }
        }
    } else {
        $Results = @{
            StatusCode = [System.Net.HttpStatusCode]::BadRequest
            Body       = 'No requests found in the body'
        }
    }

    return [HttpResponseContext]$Results
}
