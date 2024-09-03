using namespace System.Net

Function Invoke-AddScheduledItem {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Scheduler.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    if ($null -eq $Request.query.hidden) {
        $hidden = $false
    } else {
        $hidden = $true
    }
    $Result = Add-CIPPScheduledTask -Task $Request.body -hidden $hidden -DisallowDuplicateName $Request.query.DisallowDuplicateName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message $Result -Sev 'Info'

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Result }
        })

}
