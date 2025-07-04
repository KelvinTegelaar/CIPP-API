using namespace System.Net

function Invoke-RemoveAPDevice {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Deviceid = $Request.Query.ID ?? $Request.Body.ID

    try {
        if ($null -eq $TenantFilter -or $TenantFilter -eq 'null') {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$Deviceid" -type DELETE
        } else {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$Deviceid" -tenantid $TenantFilter -type DELETE
        }
        $Result = "Deleted autopilot device $Deviceid"
        Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete device $($Deviceid): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    # Force a sync, this can give "too many requests" if deleting a bunch of devices though.
    $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotSettings/sync' -tenantid $TenantFilter -type POST -body '{}'

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    }
}
