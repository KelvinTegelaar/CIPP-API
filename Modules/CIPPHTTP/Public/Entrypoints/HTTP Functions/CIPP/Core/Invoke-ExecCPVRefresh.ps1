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
    $InstanceId = Start-UpdatePermissionsOrchestrator

    return @{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body       = @{
            Results  = if ("$InstanceId" -like '*-Skipped') { 'A CPV Refresh is already running, so this request was skipped' } else { 'CPV Refresh has been triggered' }
            Metadata = @{
                InstanceId = $InstanceId
            }
        }
    }
}
