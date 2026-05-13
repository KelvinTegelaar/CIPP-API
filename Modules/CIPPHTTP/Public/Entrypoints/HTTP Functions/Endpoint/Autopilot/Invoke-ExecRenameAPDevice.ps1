Function Invoke-ExecRenameAPDevice {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Body.tenantFilter


    try {
        $DeviceId = $Request.Body.deviceId
        $SerialNumber = $Request.Body.serialNumber
        $DisplayName = $Request.Body.displayName

        # Validation
        if ($DisplayName.Length -gt 15) {
            $ValidationError = 'Display name cannot exceed 15 characters.'
        } elseif ($DisplayName -notmatch '^[a-zA-Z0-9-]+$') {
            # This regex also implicitly checks for spaces
            $ValidationError = 'Display name can only contain letters (a-z, A-Z), numbers (0-9), and hyphens (-).'
        } elseif ($DisplayName -match '^\d+$') {
            $ValidationError = 'Display name cannot consist solely of numbers.'
        }

        if ($null -ne $ValidationError) {
            $Result = "Validation failed: $ValidationError"
            $StatusCode = [HttpStatusCode]::BadRequest
        } else {
            # Validation passed, proceed with Graph API call
            $body = @{
                displayName = $DisplayName
            } | ConvertTo-Json

            New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$($DeviceId)/UpdateDeviceProperties" -tenantid $TenantFilter -body $body -method POST | Out-Null
            $Result = "Successfully renamed device '$($DeviceId)' with serial number '$($SerialNumber)' to '$($DisplayName)'"
            Write-LogMessage -Headers $User -API $APINAME -message $Result -Sev Info
            $StatusCode = [HttpStatusCode]::OK
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not rename device '$($DeviceId)' with serial number '$($SerialNumber)' to '$($DisplayName)'. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $User -API $APINAME -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })

}
