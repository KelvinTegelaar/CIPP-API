using namespace System.Net

Function Invoke-RemoveAPDevice {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $Deviceid = $Request.Query.ID

    try {
        if ($TenantFilter -eq $null -or $TenantFilter -eq 'null') {
            $GraphRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$Deviceid" -type DELETE
        } else {
            $GraphRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$Deviceid" -tenantid $TenantFilter -type DELETE
        }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -tenant $TenantFilter -API $APINAME -message "Deleted autopilot device $Deviceid" -Sev 'Info'
        $body = [pscustomobject]@{'Results' = 'Successfully deleted the autopilot device' }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -tenant $TenantFilter -API $APINAME -message "Autopilot Delete API failed for $deviceid. The error is: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed to delete device: $($_.Exception.Message)" }
    }
    #force a sync, this can give "too many requests" if deleleting a bunch of devices though.
    $GraphRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotSettings/sync' -tenantid $TenantFilter -type POST -body '{}'

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
