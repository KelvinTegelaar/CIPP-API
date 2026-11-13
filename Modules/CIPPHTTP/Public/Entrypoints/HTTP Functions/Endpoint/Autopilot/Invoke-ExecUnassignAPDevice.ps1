Function Invoke-ExecUnassignAPDevice {
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
    $TenantFilter = $Request.body.tenantFilter

    try {
        # The Autopilot device identity id
        $DeviceObject = $Request.body.device
        # Serial number, used for logging only
        $SerialNumber = $Request.body.serialNumber
        New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($DeviceObject)/unassignUserFromDevice" -tenantid $TenantFilter -body '{}' -type POST | Out-Null
        $Results = "Successfully unassigned the user from device: $DeviceObject with Serial: $SerialNumber for $($TenantFilter)"
        Write-LogMessage -Headers $User -API $APIName -tenant $TenantFilter -message $Results -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not unassign the user from $($DeviceObject) for $($TenantFilter) Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $User -API $APIName -tenant $TenantFilter -message $Results -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = [pscustomobject]@{ 'Results' = "$Results" }
        })
}
