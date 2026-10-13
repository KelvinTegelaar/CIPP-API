Function Invoke-ExecGetLocalAdminPassword {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Device.Read
    .DESCRIPTION
        Retrieves the LAPS local administrator password for a device. Platform selects Windows (the default), where guid is the Entra device ID, or macOS, where guid is the Intune managed device ID. Returns a live credential in plain text; the retrieval is written to the CIPP audit log.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint

    $Platform = $Request.Body.Platform ?? 'Windows'

    if ($Platform -notin @('Windows', 'macOS')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = [pscustomobject]@{'Results' = "Invalid Platform specified: $Platform." }
            })
    }

    try {
        $GraphRequest = if ($Platform -eq 'macOS') {
            Get-CIPPMacOSLapsPassword -Device $($request.body.guid) -TenantFilter $Request.body.TenantFilter -APIName $APINAME -Headers $Request.Headers
        } else {
            Get-CIPPLapsPassword -device $($request.body.guid) -tenantFilter $Request.body.TenantFilter -APIName $APINAME -Headers $Request.Headers
        }
        $Body = [pscustomobject]@{'Results' = $GraphRequest }
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $Body = [pscustomobject]@{'Results' = $_.Exception.Message }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_

    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
