using namespace System.Net

function Invoke-EditIntuneScript {
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

    $graphUrl = "https://graph.microsoft.com/beta"
    switch($Request.Method) {
        "GET" {
            $parms = @{
                uri = "$graphUrl/deviceManagement/deviceManagementScripts/$($Request.Query.ScriptId)"
                tenantid = $Request.Query.TenantFilter
            }

            $intuneScript = New-GraphGetRequest @parms
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $intuneScript
            })
        }
        "PATCH" {
            $parms = @{
                uri = "$graphUrl/deviceManagement/deviceManagementScripts/$($Request.Body.ScriptId)"
                tenantid = $Request.Body.TenantFilter
                body = $Request.Body.IntuneScript
            }
            $patchResult = New-GraphPOSTRequest @parms -type "PATCH"
            $body = [pscustomobject]@{'Results' = $patchResult }
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $body
            })
        }
        "POST" {
            Write-Output "Adding script"
        }
    }
}
