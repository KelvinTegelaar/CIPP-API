function Invoke-ExecDevicePasscodeAction {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Action = $Request.Body.Action
    $DeviceFilter = $Request.Body.GUID
    $TenantFilter = $Request.Body.tenantFilter

    try {
        $GraphResponse = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceFilter')/$($Action)" -type POST -tenantid $TenantFilter -body '{}'

        $Result = switch ($Action) {
            'resetPasscode' {
                if ($GraphResponse.value) {
                    "Passcode reset successfully. New passcode: $($GraphResponse.value)"
                } else {
                    "Passcode reset queued for device $DeviceFilter. The new passcode will be generated and can be retrieved from the device details."
                }
            }
            'removeDevicePasscode' {
                "Successfully removed passcode requirement from device $DeviceFilter"
            }
            default {
                "Successfully queued $Action on device $DeviceFilter"
            }
        }

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
        $Results = $Result

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to execute $Action on device $DeviceFilter : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Results = $Result
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Results }
        })
}
