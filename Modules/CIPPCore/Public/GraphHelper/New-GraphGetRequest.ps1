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

    if ($NoAuthCheck -eq $false) {
        $IsAuthorised = Get-AuthorisedRequest -Uri $uri -TenantID $tenantid
    } else {
        $IsAuthorised = $true
    }

    if ($NoAuthCheck -eq $true -or $IsAuthorised) {
        if ($scope -eq 'ExchangeOnline') {
            $headers = Get-GraphToken -tenantid $tenantid -scope 'https://outlook.office365.com/.default' -AsApp $asapp -SkipCache $skipTokenCache
        } else {
            $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp -SkipCache $skipTokenCache
        }

        if ($ComplexFilter) {
            $headers['ConsistencyLevel'] = 'eventual'
        }
        $nextURL = $uri
        if ($extraHeaders) {
            foreach ($key in $extraHeaders.Keys) {
                $headers[$key] = $extraHeaders[$key]
            }
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
            Write-Host "This is attempt $($RetryCount + 1) of $MaxRetries"
            do {
                try {
                    $GraphRequest = @{
                        Uri         = $nextURL
                        Method      = 'GET'
                        Headers     = $headers
                        ContentType = 'application/json; charset=utf-8'
                    }
                    if ($IncludeResponseHeaders) {
                        $GraphRequest.ResponseHeadersVariable = 'ResponseHeaders'
                    }

                    if ($ReturnRawResponse) {
                        $GraphRequest.SkipHttpErrorCheck = $true
                        $Data = Invoke-WebRequest @GraphRequest
                    } else {
                        $Data = (Invoke-RestMethod @GraphRequest)
                    }

                    # If we reach here, the request was successful
                    $RequestSuccessful = $true

                    if ($ReturnRawResponse) {
                        if (Test-Json -Json $Data.Content) {
                            $Content = $Data.Content | ConvertFrom-Json
                        } else {
                            $Content = $Data.Content
                        }

                        $Data | Select-Object -Property StatusCode, StatusDescription, @{Name = 'Content'; Expression = { $Content } }
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
                        $Message = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).error.message
                    } catch { $Message = $null }
                    if ($Message -eq $null) { $Message = $($_.Exception.Message) }

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
                            $WaitTime = Get-Random -Minimum 1 -Maximum 10  # Random sleep between 1-10 seconds
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
                            $Tenant.LastGraphError = $Message
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
