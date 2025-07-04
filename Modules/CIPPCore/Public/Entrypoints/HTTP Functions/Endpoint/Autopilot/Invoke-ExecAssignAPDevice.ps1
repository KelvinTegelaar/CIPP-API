using namespace System.Net

function Invoke-ExecAssignAPDevice {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Body.tenantFilter
    try {
        $UserObject = $Request.Body.user.addedFields
        $DeviceObject = $Request.Body.device
        $SerialNumber = $Request.Body.serialNumber
        $body = @{
            userPrincipalName   = $UserObject.userPrincipalName
            addressableUserName = $UserObject.addressableUserName
        } | ConvertTo-Json
        New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($DeviceObject)/UpdateDeviceProperties" -tenantid $TenantFilter -body $body -method POST | Out-Null
        Write-LogMessage -Headers $Headers -API $APIName -message "Successfully assigned device: $DeviceObject with Serial: $SerialNumber to $($UserObject.userPrincipalName) for $($TenantFilter)" -Sev Info
        $Results = "Successfully assigned device: $DeviceObject with Serial: $SerialNumber to  $($UserObject.userPrincipalName) for $($TenantFilter)"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APIName -message "Could not assign $($UserObject.userPrincipalName) to $($DeviceObject) for $($TenantFilter) Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Results = "Could not assign $($UserObject.userPrincipalName) to $($DeviceObject) for $($TenantFilter) Error: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Results }
    }
}
