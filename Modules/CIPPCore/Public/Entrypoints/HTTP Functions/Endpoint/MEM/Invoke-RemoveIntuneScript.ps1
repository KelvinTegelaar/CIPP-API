using namespace System.Net

function Invoke-RemoveIntuneScript {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $ExecutingUser = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $ExecutingUser -API $APINAME -message 'Accessed this API' -Sev Debug

    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $TenantFilter = $Request.body.TenantFilter
    $ID = $Request.body.ID
    $ScriptType = $Request.body.ScriptType
    $DisplayName = $Request.body.DisplayName

    try {

        $Endpoint = switch ($ScriptType) {
            'windows' { 'deviceManagementScripts' }
            'macOS' { 'deviceShellScripts' }
            'remediate' { 'deviceHealthScripts' }
            Default {}
        }

        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($Endpoint)/$($ID)" -tenantid $TenantFilter -type DELETE
        $Result = "Deleted $($ScriptType) script $($DisplayName)"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete $($ScriptType) script $($DisplayName). Error: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    $body = [pscustomobject]@{'Results' = "$Result" }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })

}
