Function Invoke-ExecGetLocalAdminPassword {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Device.Read
    .DESCRIPTION
        Retrieves the Windows LAPS local administrator password for a device, identified by its Entra device GUID. Returns a live credential in plain text; the retrieval is written to the CIPP audit log.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint

    try {
        $GraphRequest = Get-CIPPLapsPassword -device $($request.body.guid) -tenantFilter $Request.body.TenantFilter -APIName $APINAME -Headers $Request.Headers
        $Body = [pscustomobject]@{'Results' = $GraphRequest }

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $Body = [pscustomobject]@{'Results' = "Failed. $ErrorMessage" }

    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
