using namespace System.Net

Function Invoke-ExecAssignAPDevice {
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
    $tenantfilter = $Request.Body.TenantFilter
    try {
        $body = @{
            UserPrincipalName   = $Request.body.UserPrincipalName
            addressableUserName = $Request.body.addressableUserName
        } | ConvertTo-Json
        New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($request.body.Device)/UpdateDeviceProperties" -tenantid $TenantFilter -body $body -method POST
        $Results = "Successfully assigned device to $($Request.body.UserPrincipalName) for $($tenantfilter)"
    } catch {
        $Results = "Could not $($Request.body.UserPrincipalName) to $($Request.body.device) for $($tenantfilter) Error: $($_.Exception.Message)"
    }

    $Results = [pscustomobject]@{'Results' = "$results" }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
