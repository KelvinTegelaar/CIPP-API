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

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev Debug

    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $TenantFilter = $Request.body.TenantFilter
    $ID = $Request.body.ID
    $ScriptType = $Request.body.ScriptType
    $DisplayName = $Request.body.DisplayName

    try {

        $URI = switch ($ScriptType) {
            'Windows' {
                "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts/$($ID)"
            }
            'MacOS' {
                "https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts/$($ID)"
            }
            'Remediation' {
                "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$($ID)"
            }
            'Linux' {
                "https://graph.microsoft.com/beta/deviceManagement/ConfigurationPolicies('$($ID)')"
            }
            Default { $null }
        }

        $null = New-GraphPOSTRequest -uri $URI -type DELETE -tenantid $TenantFilter
        $Result = "Deleted $($ScriptType) script $($DisplayName) with ID: $($ID)"
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
