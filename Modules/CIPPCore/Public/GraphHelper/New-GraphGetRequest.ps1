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
        [switch]$ReturnRawResponse,
        $Headers
    )

    if ($NoAuthCheck -eq $false) {
        $IsAuthorised = Get-AuthorisedRequest -Uri $uri -TenantID $tenantid
    } else {
        $IsAuthorised = $true
    }

    if ($NoAuthCheck -eq $true -or $IsAuthorised) {
        if ($headers) {
            $headers = $Headers
        } else {
            if ($scope -eq 'ExchangeOnline') {
                $headers = Get-GraphToken -tenantid $tenantid -scope 'https://outlook.office365.com/.default' -AsApp $asapp -SkipCache $skipTokenCache
            } else {
                $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp -SkipCache $skipTokenCache
            }
        }
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

        $ReturnedData = do {
            $RetryCount = 0
            $MaxRetries = 3
            $RequestSuccessful = $false
            Write-Information "GET [ $nextURL ] | tenant: $tenantid | attempt: $($RetryCount + 1) of $MaxRetries"
            do {
                try {
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
                        } else {
                            # If no Retry-After header, use exponential backoff with jitter
                            $WaitTime = Get-Random -Minimum 1.1 -Maximum 4.1  # Random sleep between 1-4 seconds
                            Write-Warning "Rate limited (429) with no Retry-After header. Waiting $WaitTime seconds before retry. Attempt $($RetryCount + 1) of $MaxRetries. Headers: $(($HttpResponseDetails.Headers | ConvertTo-Json -Compress))"
                            $ShouldRetry = $true
                        }
                    }
                    # Check for "Resource temporarily unavailable"
                    elseif ($Message -like '*Resource temporarily unavailable*' -or $Message -like '*Too many requests*') {
                        if ($RetryCount -lt $MaxRetries) {
                            $WaitTime = Get-Random -Minimum 1.1 -Maximum 3.1  # Random sleep between 1-2 seconds
                            Write-Warning "Resource temporarily unavailable. Waiting $WaitTime seconds before retry. Attempt $($RetryCount + 1) of $MaxRetries"
                            $ShouldRetry = $true
                        }
                    }

                    if ($ShouldRetry -and $RetryCount -lt $MaxRetries) {
                        $RetryCount++
                        Start-Sleep -Seconds $WaitTime
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
        return $ReturnedData
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}
