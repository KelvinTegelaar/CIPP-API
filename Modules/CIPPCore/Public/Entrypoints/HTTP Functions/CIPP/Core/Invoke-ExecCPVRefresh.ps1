function Invoke-ExecCPVRefresh {
    <#
    .SYNOPSIS
    This endpoint is used to trigger a refresh of CPV for all tenants

    .FUNCTIONALITY
    Entrypoint

    .ROLE
    CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $InstanceId = Start-UpdatePermissionsOrchestrator

    Push-OutputBinding -Name Response -Value @{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body       = @{
            Results    = 'CPV Refresh has been triggered'
            InstanceId = $InstanceId
        }
    }
}
