function Invoke-ListGraphBulkRequest {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $GraphRequestParams = @{
        tenantid = $Request.Query.TenantFilter
        Requests = @()
    }

    if ($Request.Body.asapp) {
        $GraphRequestParams.asapp = $Request.Body.asapp
    }

    $BulkRequests = foreach ($GraphRequest in $Request.Body.Requests) {
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
        $Body = New-GraphBulkRequest @GraphRequestParams
        $Results = @{
            StatusCode = [System.Net.HttpStatusCode]::OK
            Body       = $Body
        }
    } else {
        $Results = @{
            StatusCode = [System.Net.HttpStatusCode]::BadRequest
            Body       = 'No requests found in the body'
        }
    }

    Push-OutputBinding -Name Response -Value $Results
}
