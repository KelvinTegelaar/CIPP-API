using namespace System.Net

Function Invoke-AddScheduledItem {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Result = Add-CIPPScheduledTask -Task $Request.body -hidden $false
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message $Result -Sev 'Info'

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Result }
        })

}
