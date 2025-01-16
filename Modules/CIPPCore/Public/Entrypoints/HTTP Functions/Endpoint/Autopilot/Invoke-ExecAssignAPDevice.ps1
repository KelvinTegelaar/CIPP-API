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
    $User = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $TenantFilter = $Request.body.tenantFilter


    try {
        $UserObject = $Request.body.user.addedFields
        $DeviceObject = $Request.body.device
        $SerialNumber = $Request.body.serialNumber
        $body = @{
            userPrincipalName   = $UserObject.userPrincipalName
            addressableUserName = $UserObject.addressableUserName
        } | ConvertTo-Json
        New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($DeviceObject)/UpdateDeviceProperties" -tenantid $TenantFilter -body $body -method POST | Out-Null
        Write-LogMessage -user $User -API $APINAME -message "Successfully assigned device: $DeviceObject with Serial: $SerialNumber to $($UserObject.userPrincipalName) for $($TenantFilter)" -Sev Info
        $Results = "Successfully assigned device: $DeviceObject with Serial: $SerialNumber to  $($UserObject.userPrincipalName) for $($TenantFilter)"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $User -API $APINAME -message "Could not assign $($UserObject.userPrincipalName) to $($DeviceObject) for $($TenantFilter) Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Results = "Could not assign $($UserObject.userPrincipalName) to $($DeviceObject) for $($TenantFilter) Error: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    $Results = [pscustomobject]@{'Results' = "$results" }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
