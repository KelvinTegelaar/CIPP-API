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

    # Initialize per-request timing
    $HttpTimings = @{}
    $HttpTotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Initialize AsyncLocal storage for thread-safe per-invocation context
    if (-not $script:CippInvocationIdStorage) {
        $script:CippInvocationIdStorage = [System.Threading.AsyncLocal[string]]::new()
    }
    if (-not $script:CippAllowedTenantsStorage) {
        $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()
    }
    if (-not $script:CippAllowedGroupsStorage) {
        $script:CippAllowedGroupsStorage = [System.Threading.AsyncLocal[object]]::new()
    }
    if (-not $script:CippUserRolesStorage) {
        $script:CippUserRolesStorage = [System.Threading.AsyncLocal[hashtable]]::new()
    }

    # Initialize user roles cache for this request
    if (-not $script:CippUserRolesStorage.Value) {
        $script:CippUserRolesStorage.Value = @{}
    }

    # Set InvocationId in AsyncLocal storage for console logging correlation
    if ($global:TelemetryClient -and $TriggerMetadata.InvocationId) {
        $script:CippInvocationIdStorage.Value = $TriggerMetadata.InvocationId
    }

    $FunctionName = 'Invoke-{0}' -f $Request.Params.CIPPEndpoint
    Write-Information "API Endpoint: $($Request.Params.CIPPEndpoint) | Frontend Version: $($Request.Headers.'X-CIPP-Version' ?? 'Not specified')"

    # Check if endpoint is disabled via feature flags
    $FeatureFlags = Get-CIPPFeatureFlag
    $DisabledEndpoint = $FeatureFlags | Where-Object {
        $_.Enabled -eq $false -and $_.Endpoints -contains $Request.Params.CIPPEndpoint
    } | Select-Object -First 1

    if ($DisabledEndpoint) {
        Write-Information "Endpoint $($Request.Params.CIPPEndpoint) is disabled via feature flag: $($DisabledEndpoint.Name)"
        $HttpTotalStopwatch.Stop()
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::ServiceUnavailable
                Body       = "This feature has been disabled: $($DisabledEndpoint.Description)"
            })
    }

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
                $swAccess = [System.Diagnostics.Stopwatch]::StartNew()
                $Access = Test-CIPPAccess -Request $Request
                $swAccess.Stop()
                $HttpTimings['AccessCheck'] = $swAccess.Elapsed.TotalMilliseconds
                if ($FunctionName -eq 'Invoke-Me') {
                    $HttpTotalStopwatch.Stop()
                    $HttpTimings['Total'] = $HttpTotalStopwatch.Elapsed.TotalMilliseconds
                    $HttpTimingsRounded = [ordered]@{}
                    foreach ($Key in ($HttpTimings.Keys | Sort-Object)) { $HttpTimingsRounded[$Key] = [math]::Round($HttpTimings[$Key], 2) }
                    Write-Debug "#### HTTP Request Timings #### $($HttpTimingsRounded | ConvertTo-Json -Compress)"
                    return $Access
                }
            } catch {
                Write-Information "Access denied for $FunctionName : $($_.Exception.Message)"
                $HttpTotalStopwatch.Stop()
                $HttpTimings['Total'] = $HttpTotalStopwatch.Elapsed.TotalMilliseconds
                $HttpTimingsRounded = [ordered]@{}
                foreach ($Key in ($HttpTimings.Keys | Sort-Object)) { $HttpTimingsRounded[$Key] = [math]::Round($HttpTimings[$Key], 2) }
                Write-Debug "#### HTTP Request Timings #### $($HttpTimingsRounded | ConvertTo-Json -Compress)"
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body       = $_.Exception.Message
                    })
            }
            $swTenants = [System.Diagnostics.Stopwatch]::StartNew()
            $AllowedTenants = Test-CippAccess -Request $Request -TenantList
            $swTenants.Stop()
            $HttpTimings['AllowedTenants'] = $swTenants.Elapsed.TotalMilliseconds

            $swGroups = [System.Diagnostics.Stopwatch]::StartNew()
            $AllowedGroups = Test-CippAccess -Request $Request -GroupList
            $swGroups.Stop()
            $HttpTimings['AllowedGroups'] = $swGroups.Elapsed.TotalMilliseconds

            if ($AllowedTenants -notcontains 'AllTenants') {
                Write-Warning 'Limiting tenant access'
                $script:CippAllowedTenantsStorage.Value = $AllowedTenants
            }
            if ($AllowedGroups -notcontains 'AllGroups') {
                Write-Warning 'Limiting group access'
                $script:CippAllowedGroupsStorage.Value = $AllowedGroups
            }

            try {
                Write-Information "Access: $Access"
                Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message 'Accessed this API' -Sev 'Debug'
                if ($Access) {
                    # Prepare telemetry metadata for HTTP API call
                    $metadata = @{
                        Endpoint     = $Request.Params.CIPPEndpoint
                        FunctionName = $FunctionName
                        Method       = $Request.Method
                        TriggerType  = 'HTTP'
                    }

                    # Add tenant filter if present
                    if ($Request.Query.TenantFilter) {
                        $metadata['Tenant'] = $Request.Query.TenantFilter
                    } elseif ($Request.Body.TenantFilter) {
                        $metadata['Tenant'] = $Request.Body.TenantFilter
                    }

                    # Add user info if available
                    if ($Request.Headers.'x-ms-client-principal-name') {
                        $metadata['User'] = $Request.Headers.'x-ms-client-principal-name'
                    }

                    # Wrap the API call execution with telemetry
                    $swInvoke = [System.Diagnostics.Stopwatch]::StartNew()
                    $Response = Measure-CippTask -TaskName $Request.Params.CIPPEndpoint -Metadata $metadata -Script { & $FunctionName @HttpTrigger }
                    $swInvoke.Stop()
                    $HttpTimings['InvokeEndpoint'] = $swInvoke.Elapsed.TotalMilliseconds

                    # Filter to only return HttpResponseContext objects
                    $HttpResponse = $Response | Where-Object { $_.PSObject.TypeNames -eq 'Microsoft.Azure.Functions.PowerShellWorker.HttpResponseContext' }
                    if ($HttpResponse) {
                        # Return the first valid HttpResponseContext found
                        $HttpTotalStopwatch.Stop()
                        $HttpTimings['Total'] = $HttpTotalStopwatch.Elapsed.TotalMilliseconds
                        $HttpTimingsRounded = [ordered]@{}
                        foreach ($Key in ($HttpTimings.Keys | Sort-Object)) { $HttpTimingsRounded[$Key] = [math]::Round($HttpTimings[$Key], 2) }
                        Write-Debug "#### HTTP Request Timings #### $($HttpTimingsRounded | ConvertTo-Json -Compress)"
                        return ([HttpResponseContext]($HttpResponse | Select-Object -First 1))
                    } else {
                        # If no valid response context found, create a default success response
                        if ($Response.PSObject.Properties.Name -contains 'StatusCode' -and $Response.PSObject.Properties.Name -contains 'Body') {
                            $HttpTotalStopwatch.Stop()
                            $HttpTimings['Total'] = $HttpTotalStopwatch.Elapsed.TotalMilliseconds
                            $HttpTimingsRounded = [ordered]@{}
                            foreach ($Key in ($HttpTimings.Keys | Sort-Object)) { $HttpTimingsRounded[$Key] = [math]::Round($HttpTimings[$Key], 2) }
                            Write-Debug "#### HTTP Request Timings #### $($HttpTimingsRounded | ConvertTo-Json -Compress)"
                            return ([HttpResponseContext]@{
                                    StatusCode = $Response.StatusCode
                                    Body       = $Response.Body
                                })
                        } else {
                            $HttpTotalStopwatch.Stop()
                            $HttpTimings['Total'] = $HttpTotalStopwatch.Elapsed.TotalMilliseconds
                            $HttpTimingsRounded = [ordered]@{}
                            foreach ($Key in ($HttpTimings.Keys | Sort-Object)) { $HttpTimingsRounded[$Key] = [math]::Round($HttpTimings[$Key], 2) }
                            Write-Debug "#### HTTP Request Timings #### $($HttpTimingsRounded | ConvertTo-Json -Compress)"
                            return ([HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::OK
                                    Body       = $Response
                                })
                        }
                    }
                }
            } catch {
                Write-Warning "Exception occurred on HTTP trigger ($FunctionName): $($_.Exception.Message)"
                $HttpTotalStopwatch.Stop()
                $HttpTimings['Total'] = $HttpTotalStopwatch.Elapsed.TotalMilliseconds
                $HttpTimingsRounded = [ordered]@{}
                foreach ($Key in ($HttpTimings.Keys | Sort-Object)) { $HttpTimingsRounded[$Key] = [math]::Round($HttpTimings[$Key], 2) }
                Write-Debug "#### HTTP Request Timings #### $($HttpTimingsRounded | ConvertTo-Json -Compress)"
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::InternalServerError
                        Body       = $_.Exception.Message
                    })
            }
        } else {
            $HttpTotalStopwatch.Stop()
            $HttpTimings['Total'] = $HttpTotalStopwatch.Elapsed.TotalMilliseconds
            $HttpTimingsRounded = [ordered]@{}
            foreach ($Key in ($HttpTimings.Keys | Sort-Object)) { $HttpTimingsRounded[$Key] = [math]::Round($HttpTimings[$Key], 2) }
            Write-Debug "#### HTTP Request Timings #### $($HttpTimingsRounded | ConvertTo-Json -Compress)"
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = 'Endpoint not found'
                })
        }
    } else {
        $HttpTotalStopwatch.Stop()
        $HttpTimings['Total'] = $HttpTotalStopwatch.Elapsed.TotalMilliseconds
        $HttpTimingsRounded = [ordered]@{}
        foreach ($Key in ($HttpTimings.Keys | Sort-Object)) { $HttpTimingsRounded[$Key] = [math]::Round($HttpTimings[$Key], 2) }
        Write-Debug "#### HTTP Request Timings #### $($HttpTimingsRounded | ConvertTo-Json -Compress)"
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::PreconditionFailed
                Body       = 'Request not processed'
            })
    }
}
