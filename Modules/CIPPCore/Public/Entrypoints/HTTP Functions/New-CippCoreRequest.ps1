using namespace System.Net
using namespace Microsoft.Azure.Functions.PowerShellWorker
function New-CippCoreRequest {
    <#
    .SYNOPSIS
        Main entrypoint for all HTTP triggered functions in CIPP
    .DESCRIPTION
        This function is the main entry point for all HTTP triggered functions in CIPP. It routes requests to the appropriate function based on the CIPPEndpoint parameter in the request.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param($Request, $TriggerMetadata)

    $FunctionName = 'Invoke-{0}' -f $Request.Params.CIPPEndpoint
    Write-Information "API: $($Request.Params.CIPPEndpoint)"

    $HttpTrigger = @{
        Request         = [pscustomobject]($Request)
        TriggerMetadata = $TriggerMetadata
    }

    if ($PSCmdlet.ShouldProcess("Processing request for $($Request.Params.CIPPEndpoint)")) {
        if ((Get-Command -Name $FunctionName -ErrorAction SilentlyContinue) -or $FunctionName -eq 'Invoke-Me') {
            try {
                $Access = Test-CIPPAccess -Request $Request
                if ($FunctionName -eq 'Invoke-Me') {
                    return $Access
                }
            } catch {
                Write-Information "Access denied for $FunctionName : $($_.Exception.Message)"
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body       = $_.Exception.Message
                    })
            }

            try {
                Write-Information "Access: $Access"
                Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message 'Accessed this API' -Sev 'Debug'
                if ($Access) {
                    $Response = & $FunctionName @HttpTrigger
                    # Filter to only return HttpResponseContext objects
                    $HttpResponse = $Response | Where-Object { $_.PSObject.TypeNames -eq 'Microsoft.Azure.Functions.PowerShellWorker.HttpResponseContext' }
                    if ($HttpResponse) {
                        # Return the first valid HttpResponseContext found
                        return ([HttpResponseContext]($HttpResponse | Select-Object -First 1))
                    } else {
                        # If no valid response context found, create a default success response
                        return ([HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::OK
                                Body       = $Response
                            })
                    }
                }
            } catch {
                Write-Warning "Exception occurred on HTTP trigger ($FunctionName): $($_.Exception.Message)"
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::InternalServerError
                        Body       = $_.Exception.Message
                    })
            }
        } else {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = 'Endpoint not found'
                })
        }
    } else {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::PreconditionFailed
                Body       = 'Request not processed'
            })
    }
}
