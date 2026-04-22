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

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.TenantFilter
    $ID = $Request.Body.ID
    $ScriptType = $Request.Body.ScriptType
    $DisplayName = $Request.Body.DisplayName

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
            default { $null }
        }

        $null = New-GraphPOSTRequest -uri $URI -type DELETE -tenantid $TenantFilter
        $Result = "Deleted $($ScriptType) script $($DisplayName) with ID: $($ID)"
        Write-LogMessage -headers $Headers -API $APINAME -tenant $Tenant -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete $($ScriptType) script $($DisplayName). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APINAME -tenant $Tenant -message $Result -Sev 'Error'
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = "$Result" }
        })

}
