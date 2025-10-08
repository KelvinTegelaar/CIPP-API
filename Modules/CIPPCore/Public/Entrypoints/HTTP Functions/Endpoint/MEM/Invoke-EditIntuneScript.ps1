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

    $graphUrl = 'https://graph.microsoft.com/beta'

    # Define the endpoint based on script type
    function Get-ScriptEndpoint {
        param (
            [Parameter(Mandatory = $true)]
            [string]$ScriptType
        )

        switch ($ScriptType) {
            'Windows' { return 'deviceManagement/deviceManagementScripts' }
            'MacOS' { return 'deviceManagement/deviceShellScripts' }
            'Remediation' { return 'deviceManagement/deviceHealthScripts' }
            'Linux' { return 'deviceManagement/configurationPolicies' }
            default { return 'deviceManagement/deviceManagementScripts' }
        }
    }

    switch ($Request.Method) {
        'GET' {
            # First get the script type by querying the script ID
            $scriptId = $Request.Query.ScriptId
            $scriptTypeFound = $false

            # Try each endpoint to find the script
            foreach ($scriptType in @('Windows', 'MacOS', 'Remediation', 'Linux')) {
                $endpoint = Get-ScriptEndpoint -ScriptType $scriptType
                $parms = @{
                    uri      = "$graphUrl/$endpoint/$scriptId"
                    tenantid = $Request.Query.TenantFilter
                }

                try {
                    $intuneScript = New-GraphGetRequest @parms -ErrorAction Stop
                    if ($intuneScript) {
                        $intuneScript | Add-Member -MemberType NoteProperty -Name scriptType -Value $scriptType -Force
                        $scriptTypeFound = $true
                        break
                    }
                } catch {
                    # Script not found in this endpoint, try next one
                    continue
                }
            }

            if ($scriptTypeFound) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = $intuneScript
                    })
            } else {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body       = "Script with ID $scriptId was not found in any endpoint."
                    })
            }
        }
        'PATCH' {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = "Method $($Request.Method) is not supported."
                })
        }
        'POST' {
            # Parse the script data to determine type
            $scriptData = $Request.Body.IntuneScript | ConvertFrom-Json
            $scriptType = $Request.Body.ScriptType

            if (-not $scriptType) {
                # Try to determine script type from the request body
                if ($scriptData.PSObject.Properties.Name -contains '@odata.type') {
                    switch ($scriptData.'@odata.type') {
                        '#microsoft.graph.deviceManagementScript' { $scriptType = 'Windows' }
                        '#microsoft.graph.deviceShellScript' { $scriptType = 'MacOS' }
                        '#microsoft.graph.deviceHealthScript' { $scriptType = 'Remediation' }
                        default {
                            if ($scriptData.platforms -eq 'linux' -and $scriptData.templateReference.templateFamily -eq 'deviceConfigurationScripts') {
                                $scriptType = 'Linux'
                            } else {
                                $scriptType = 'Windows' # Default to Windows if no definitive type found
                            }
                        }
                    }
                }
            }

            $endpoint = Get-ScriptEndpoint -ScriptType $scriptType
            $parms = @{
                uri      = "$graphUrl/$endpoint/$($Request.Body.ScriptId)"
                tenantid = $Request.Body.TenantFilter
                body     = $Request.Body.IntuneScript
            }

            try {
                $patchResult = New-GraphPOSTRequest @parms -type 'PATCH'
                $body = [pscustomobject]@{'Results' = $patchResult }
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = $body
                    })
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = "Failed to update script: $($ErrorMessage.NormalizedError)"
                    })
            }
        }
    }
}
