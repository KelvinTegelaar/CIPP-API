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
    Write-Information "API Endpoint: $($Request.Params.CIPPEndpoint) | Frontend Version: $($Request.Headers.'X-CIPP-Version' ?? 'Not specified')"

    if ($Request.Headers.'X-CIPP-Version') {
        $Table = Get-CippTable -tablename 'Version'
        $FrontendVer = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Version' and RowKey eq 'frontend'"

        if (!$FrontendVer -or ([semver]$FrontendVer.Version -lt [semver]$Request.Headers.'X-CIPP-Version')) {
            Add-CIPPAzDataTableEntity @Table -Entity ([pscustomobject]@{
                    PartitionKey = 'Version'
                    RowKey       = 'frontend'
                    Version      = $Request.Headers.'X-CIPP-Version'
                }) -Force
        } elseif ([semver]$FrontendVer.Version -gt [semver]$Request.Headers.'X-CIPP-Version') {
            Write-Warning "Client version $($Request.Headers.'X-CIPP-Version') is older than the current frontend version $($FrontendVer.Version)"
        }
    }

    $HttpTrigger = @{
        Request         = [pscustomobject]($Request)
        TriggerMetadata = $TriggerMetadata
    }

    if ($PSCmdlet.ShouldProcess("Processing request for $($Request.Params.CIPPEndpoint)")) {
        # Set script scope variables for Graph API to indicate HTTP request/high priority
        $script:XMsThrottlePriority = 'high'

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

            $AllowedTenants = Test-CippAccess -Request $Request -TenantList
            $AllowedGroups = Test-CippAccess -Request $Request -GroupList

            if ($AllowedTenants -notcontains 'AllTenants') {
                Write-Warning 'Limiting tenant access'
                $script:AllowedTenants = $AllowedTenants
            }
            if ($AllowedGroups -notcontains 'AllGroups') {
                Write-Warning 'Limiting group access'
                $script:AllowedGroups = $AllowedGroups
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
                        if ($Response.PSObject.Properties.Name -contains 'StatusCode' -and $Response.PSObject.Properties.Name -contains 'Body') {
                            return ([HttpResponseContext]@{
                                    StatusCode = $Response.StatusCode
                                    Body       = $Response.Body
                                })
                        } else {
                            return ([HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::OK
                                    Body       = $Response
                                })
                        }
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
