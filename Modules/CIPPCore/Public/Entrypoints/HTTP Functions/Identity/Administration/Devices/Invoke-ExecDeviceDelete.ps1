using namespace System.Net

Function Invoke-ExecDeviceDelete {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Device.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.


    try {
        $url = "https://graph.microsoft.com/beta/devices/$($request.query.id)"
        if ($Request.query.action -eq 'delete') {
            $ActionResult = New-GraphPOSTRequest -uri $url -type DELETE -tenantid $Request.Query.TenantFilter
        } elseif ($Request.query.action -eq 'disable') {
            $ActionResult = New-GraphPOSTRequest -uri $url -type PATCH -tenantid $Request.Query.TenantFilter -body '{"accountEnabled": false }'
        } elseif ($Request.query.action -eq 'enable') {
            $ActionResult = New-GraphPOSTRequest -uri $url -type PATCH -tenantid $Request.Query.TenantFilter -body '{"accountEnabled": true }'
        }
        Write-Host $ActionResult
        $body = [pscustomobject]@{'Results' = "Executed action $($Request.query.action) on $($Request.query.id)" }
    } catch {
        $body = [pscustomobject]@{'Results' = "Failed to queue action $($Request.query.action) on $($request.query.id): $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
