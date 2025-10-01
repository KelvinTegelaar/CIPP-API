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


    $InstanceId = Start-UpdatePermissionsOrchestrator

    return @{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body       = @{
            Results    = 'CPV Refresh has been triggered'
            InstanceId = $InstanceId
        }
    }
}
