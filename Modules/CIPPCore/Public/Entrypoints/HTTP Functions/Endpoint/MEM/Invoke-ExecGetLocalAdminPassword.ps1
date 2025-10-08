Function Invoke-ExecGetLocalAdminPassword {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Device.Read
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
