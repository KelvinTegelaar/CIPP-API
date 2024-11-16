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
        tenantid = $Request.Body.tenantFilter
        Requests = @()
    }

    if ($Request.Body.asapp) {
        $GraphRequestParams.asapp = $Request.Body.asApp
    }

    $BulkRequests = foreach ($GraphRequest in $Request.Body.requests) {
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

    Push-OutputBinding -Name Response -Value $Results
}
