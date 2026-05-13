Function Invoke-ExecAssignAPDevice {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $User = $Request.Headers
    Write-LogMessage -Headers $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'
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
        Write-LogMessage -Headers $User -API $APINAME -message "Successfully assigned device: $DeviceObject with Serial: $SerialNumber to $($UserObject.userPrincipalName) for $($TenantFilter)" -Sev Info
        $Results = "Successfully assigned device: $DeviceObject with Serial: $SerialNumber to  $($UserObject.userPrincipalName) for $($TenantFilter)"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $User -API $APINAME -message "Could not assign $($UserObject.userPrincipalName) to $($DeviceObject) for $($TenantFilter) Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Results = "Could not assign $($UserObject.userPrincipalName) to $($DeviceObject) for $($TenantFilter) Error: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    $Results = [pscustomobject]@{'Results' = "$results" }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
