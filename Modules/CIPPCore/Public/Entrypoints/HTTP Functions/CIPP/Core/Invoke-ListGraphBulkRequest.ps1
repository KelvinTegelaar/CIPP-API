function Invoke-ListGraphBulkRequest {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Body.tenantFilter
    $AsApp = $Request.Body.asApp
    $Requests = $Request.Body.requests

    $GraphRequestParams = @{
        tenantid = $TenantFilter
        Requests = @()
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

    Push-OutputBinding -Name Response -Value $Results
}
