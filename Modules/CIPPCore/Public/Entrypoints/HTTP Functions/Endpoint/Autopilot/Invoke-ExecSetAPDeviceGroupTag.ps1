Function Invoke-ExecSetAPDeviceGroupTag {
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

    $TenantFilter = $Request.Body.tenantFilter

    try {
        $DeviceId = $Request.Body.deviceId
        $SerialNumber = $Request.Body.serialNumber
        $GroupTag = $Request.Body.groupTag

        # Validation - GroupTag can be empty, but if provided, validate it
        if ($null -ne $GroupTag -and $GroupTag -ne '' -and $GroupTag.Length -gt 128) {
            $ValidationError = 'Group tag cannot exceed 128 characters.'
        }

        if ($null -ne $ValidationError) {
            $Result = "Validation failed: $ValidationError"
            $StatusCode = [HttpStatusCode]::BadRequest
        } else {
            # Validation passed, proceed with Graph API call
            $body = @{
                groupTag = $GroupTag
            } | ConvertTo-Json

            New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($DeviceId)/UpdateDeviceProperties" -tenantid $TenantFilter -body $body -method POST | Out-Null
            $Result = "Successfully updated group tag for device '$($DeviceId)' with serial number '$($SerialNumber)' to '$($GroupTag)'"
            Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Info
            $StatusCode = [HttpStatusCode]::OK
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not update group tag for device '$($DeviceId)' with serial number '$($SerialNumber)' to '$($GroupTag)'. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
