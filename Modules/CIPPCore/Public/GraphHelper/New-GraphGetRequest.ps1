function New-GraphGetRequest {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [string]$uri,
        [string]$tenantid,
        [string]$scope,
        $AsApp,
        [bool]$noPagination,
        $NoAuthCheck = $false,
        [bool]$skipTokenCache,
        $Caller,
        [switch]$ComplexFilter,
        [switch]$CountOnly,
        [switch]$IncludeResponseHeaders,
        [hashtable]$extraHeaders,
        [switch]$ReturnRawResponse
    )

    $Timings = @{}
    $TotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $SwAuthCheck = [System.Diagnostics.Stopwatch]::StartNew()
    if ($NoAuthCheck -eq $false) {
        $IsAuthorised = Get-AuthorisedRequest -Uri $uri -TenantID $tenantid
    } else {
        $IsAuthorised = $true
    }
    $SwAuthCheck.Stop()
    $Timings['AuthCheck'] = $SwAuthCheck.Elapsed.TotalMilliseconds

    if ($NoAuthCheck -eq $true -or $IsAuthorised) {
        $SwTokenGet = [System.Diagnostics.Stopwatch]::StartNew()
        if ($scope -eq 'ExchangeOnline') {
            $headers = Get-GraphToken -tenantid $tenantid -scope 'https://outlook.office365.com/.default' -AsApp $asapp -SkipCache $skipTokenCache
        } else {
            $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp -SkipCache $skipTokenCache
        }
        $SwTokenGet.Stop()
        $Timings['TokenGet'] = $SwTokenGet.Elapsed.TotalMilliseconds

        if ($ComplexFilter) {
            $headers['ConsistencyLevel'] = 'eventual'
        }

        if ($script:XMsThrottlePriority) {
            $headers['x-ms-throttle-priority'] = $script:XMsThrottlePriority
        }

        $nextURL = $uri
        if ($extraHeaders) {
            foreach ($key in $extraHeaders.Keys) {
                $headers[$key] = $extraHeaders[$key]
            }
        }

        if (!$headers['User-Agent']) {
            $headers['User-Agent'] = "CIPP/$($global:CippVersion ?? '1.0')"
        }

        $SwTenantLookup = [System.Diagnostics.Stopwatch]::StartNew()
        # Track consecutive Graph API failures
        $TenantsTable = Get-CippTable -tablename Tenants
        $Filter = "PartitionKey eq 'Tenants' and (defaultDomainName eq '{0}' or customerId eq '{0}')" -f $tenantid
        $Tenant = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter
        if (!$Tenant) {
            $Tenant = @{
                GraphErrorCount = 0
                LastGraphError  = ''
                PartitionKey    = 'TenantFailed'
                RowKey          = 'Failed'
            }
        }
        $SwTenantLookup.Stop()
        $Timings['TenantLookup'] = $SwTenantLookup.Elapsed.TotalMilliseconds

        $SwApiCalls = 0
        $SwRetryWait = 0
        $SwErrorHandling = 0
        $ApiCallCount = 0

        $ReturnedData = do {
            $RetryCount = 0
            $MaxRetries = 3
            $RequestSuccessful = $false
            Write-Information "GET [ $nextURL ] | tenant: $tenantid | attempt: $($RetryCount + 1) of $MaxRetries"
            do {
                try {
                    $SwCall = [System.Diagnostics.Stopwatch]::StartNew()
                    $GraphRequest = @{
                        Uri         = $nextURL
                        Method      = 'GET'
                        Headers     = $headers
                        ContentType = 'application/json; charset=utf-8'
                    }

                    if ($ReturnRawResponse) {
                        $GraphRequest.SkipHttpErrorCheck = $true
                        $Data = Invoke-WebRequest @GraphRequest
                    } else {
                        $GraphRequest.ResponseHeadersVariable = 'ResponseHeaders'
                        $Data = (Invoke-RestMethod @GraphRequest)
                        $script:LastGraphResponseHeaders = $ResponseHeaders
                    }
                    $SwCall.Stop()
                    $SwApiCalls += $SwCall.Elapsed.TotalMilliseconds
                    $ApiCallCount++

                    # If we reach here, the request was successful
                    $RequestSuccessful = $true

                    if ($ReturnRawResponse) {
                        try {
                            if ($Data.Content -and (Test-Json -Json $Data.Content -ErrorAction Stop)) {
                                $Content = $Data.Content | ConvertFrom-Json
                            } else {
                                $Content = $Data.Content
                            }
                        } catch {
                            $Content = $Data.Content
                        }

                        [PSCustomObject]@{
                            StatusCode        = $Data.StatusCode
                            StatusDescription = $Data.StatusDescription
                            Content           = $Content
                        }
                        $nextURL = $null
                    } elseif ($CountOnly) {
                        $Data.'@odata.count'
                        $NextURL = $null
                    } else {
                        if ($Data.PSObject.Properties.Name -contains 'value') { $data.value } else { $Data }
                        if ($noPagination -eq $true) {
                            if ($Caller -eq 'Get-GraphRequestList') {
                                @{ 'nextLink' = $data.'@odata.nextLink' }
                            }
                            $nextURL = $null
                        } else {
                            $NextPageUriFound = $false
                            if ($IncludeResponseHeaders) {
                                if ($ResponseHeaders.NextPageUri) {
                                    $NextURL = $ResponseHeaders.NextPageUri
                                    $NextPageUriFound = $true
                                }
                            }
                            if (!$NextPageUriFound) {
                                $nextURL = $data.'@odata.nextLink'
                            }
                        }
                    }
                } catch {
                    $SwError = [System.Diagnostics.Stopwatch]::StartNew()
                    $ShouldRetry = $false
                    $WaitTime = 0
                    try {
                        $MessageObj = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($MessageObj.error) {
                            $MessageObj | Add-Member -NotePropertyName 'url' -NotePropertyValue $nextURL -Force
                            $Message = $MessageObj.error.message -ne '' ? $MessageObj.error.message : $MessageObj.error.code
                        }
                    } catch { $Message = $null }

                    if ([string]::IsNullOrEmpty($Message)) {
                        $Message = $($_.Exception.Message)
                        $MessageObj = @{
                            error = @{
                                code    = $_.Exception.GetType().FullName
                                message = $Message
                                url     = $nextURL
                            }
                        }
                    }

                    # Check for 429 Too Many Requests
                    if ($_.Exception.Response.StatusCode -eq 429) {
                        $RetryAfterHeader = $_.Exception.Response.Headers['Retry-After']
                        if ($RetryAfterHeader) {
                            $WaitTime = [int]$RetryAfterHeader
                            Write-Warning "Rate limited (429). Waiting $WaitTime seconds before retry. Attempt $($RetryCount + 1) of $MaxRetries"
                            $ShouldRetry = $true
                        }
                    }
                    # Check for "Resource temporarily unavailable"
                    elseif ($Message -like '*Resource temporarily unavailable*') {
                        if ($RetryCount -lt $MaxRetries) {
                            $ShouldRetry = $true
                        }
                    }
                    $SwError.Stop()
                    $SwErrorHandling += $SwError.Elapsed.TotalMilliseconds

                    if ($ShouldRetry -and $RetryCount -lt $MaxRetries) {
                        $RetryCount++
                        $SwWait = [System.Diagnostics.Stopwatch]::StartNew()
                        Start-Sleep -Seconds $WaitTime
                        $SwWait.Stop()
                        $SwRetryWait += $SwWait.Elapsed.TotalMilliseconds
                    } else {
                        # Final failure - update tenant error tracking and throw
                        if ($Message -ne 'Request not applicable to target tenant.' -and $Tenant) {
                            $Tenant.LastGraphError = [string]($MessageObj | ConvertTo-Json -Compress)
                            if ($Tenant.PSObject.Properties.Name -notcontains 'GraphErrorCount') {
                                $Tenant | Add-Member -MemberType NoteProperty -Name 'GraphErrorCount' -Value 0 -Force
                            }
                            $Tenant.GraphErrorCount++
                            Update-AzDataTableEntity -Force @TenantsTable -Entity $Tenant
                        }
                        throw $Message
                    }
                }
            } while (-not $RequestSuccessful -and $RetryCount -le $MaxRetries)
        } until ([string]::IsNullOrEmpty($NextURL) -or $NextURL -is [object[]] -or ' ' -eq $NextURL)

        $Timings['ApiCalls'] = $SwApiCalls
        $Timings['RetryWait'] = $SwRetryWait
        $Timings['ErrorHandling'] = $SwErrorHandling

        $SwTenantUpdate = [System.Diagnostics.Stopwatch]::StartNew()
        if ($Tenant.PSObject.Properties.Name -notcontains 'LastGraphError') {
            $Tenant | Add-Member -MemberType NoteProperty -Name 'LastGraphError' -Value '' -Force
        } else {
            $Tenant.LastGraphError = ''
        }
        if ($Tenant.PSObject.Properties.Name -notcontains 'GraphErrorCount') {
            $Tenant | Add-Member -MemberType NoteProperty -Name 'GraphErrorCount' -Value 0 -Force
        } else {
            $Tenant.GraphErrorCount = 0
        }
        Update-AzDataTableEntity -Force @TenantsTable -Entity $Tenant
        $SwTenantUpdate.Stop()
        $Timings['TenantUpdate'] = $SwTenantUpdate.Elapsed.TotalMilliseconds

        $TotalStopwatch.Stop()
        $TotalMs = $TotalStopwatch.Elapsed.TotalMilliseconds

        $TimingReport = "GRAPH_GET: Total: $([math]::Round($TotalMs, 2))ms | Calls: $ApiCallCount"
        foreach ($Key in ($Timings.Keys | Sort-Object)) {
            $Ms = [math]::Round($Timings[$Key], 2)
            $Pct = [math]::Round(($Timings[$Key] / $TotalMs) * 100, 1)
            $TimingReport += " | $Key : $Ms ms ($Pct %)"
        }
        Write-Host $TimingReport

        return $ReturnedData
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}
