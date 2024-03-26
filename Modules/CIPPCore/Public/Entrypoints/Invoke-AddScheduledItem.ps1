using namespace System.Net

Function Invoke-AddScheduledItem {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Result = Add-CIPPScheduledTask -Task $Request.body -hidden $false

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Result }
        })

}
