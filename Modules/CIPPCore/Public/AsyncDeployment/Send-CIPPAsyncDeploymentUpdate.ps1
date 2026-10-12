function Send-CIPPAsyncDeploymentUpdate {
    <#
    .SYNOPSIS
    Push a changed async deployment row to the users watching its job

    .DESCRIPTION
    Sends the row, in the Get-CIPPAsyncDeployment shape, over Craft's realtime channel so a progress
    view updates without asking the API again. Does nothing outside CIPP-NG.

    .PARAMETER JobId
    The deployment job id

    .PARAMETER Row
    The table row as just written

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter(Mandatory = $true)]
        $Row
    )

    if ($env:CIPPNG -ne 'true') { return }
    try {
        $Data = ConvertTo-CIPPAsyncDeploymentRow -Row $Row -LastUpdate (Get-Date).ToUniversalTime()
        Send-CIPPRealtimeEvent -JobId $JobId -Data $Data
    } catch {
        Write-Verbose "Async deployment update not sent: $($_.Exception.Message)"
    }
}
