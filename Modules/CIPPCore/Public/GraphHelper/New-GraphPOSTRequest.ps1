
function New-GraphPOSTRequest {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param(
        $uri,
        $tenantid,
        $body,
        $type = 'POST',
        $scope,
        $AsApp,
        $NoAuthCheck,
        $skipTokenCache,
        $AddedHeaders,
        $contentType,
        $IgnoreErrors = $false,
        $returnHeaders = $false,
        $maxRetries = 3,
        $ScheduleRetry = $false
    )

    if ($NoAuthCheck -or (Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp -SkipCache $skipTokenCache
        if ($AddedHeaders) {
            foreach ($header in $AddedHeaders.GetEnumerator()) {
                $headers.Add($header.Key, $header.Value)
            }
        }

        if (!$headers['User-Agent']) {
            $headers['User-Agent'] = "CIPP/$($global:CippVersion ?? '1.0')"
        }

        if (!$contentType) {
            $contentType = 'application/json; charset=utf-8'
        }

        $body = Get-CIPPTextReplacement -TenantFilter $tenantid -Text $body -EscapeForJson

        $RetryCount = 0
        $RequestSuccessful = $false
        do {
            try {
                Write-Information "$($type.ToUpper()) [ $uri ] | tenant: $tenantid | attempt: $($RetryCount + 1) of $maxRetries"
                $ReturnedData = (Invoke-RestMethod -Uri $($uri) -Method $TYPE -Body $body -Headers $headers -ContentType $contentType -SkipHttpErrorCheck:$IgnoreErrors -ResponseHeadersVariable responseHeaders)
                $RequestSuccessful = $true
            } catch {
                $ShouldRetry = $false
                $WaitTime = 0
                $Message = if ($_.ErrorDetails.Message) {
                    Get-NormalizedError -Message $_.ErrorDetails.Message
                } else {
                    $_.Exception.message
                }

                # Check for 429 Too Many Requests
                if ($_.Exception.Response.StatusCode -eq 429) {
                    $RetryAfterHeader = $_.Exception.Response.Headers['Retry-After']
                    if ($RetryAfterHeader) {
                        $WaitTime = [int]$RetryAfterHeader
                        Write-Warning "Rate limited (429). Waiting $WaitTime seconds before retry. Attempt $($RetryCount + 1) of $maxRetries"
                        $ShouldRetry = $true
                    }
                }
                # Check for "Resource temporarily unavailable"
                elseif ($Message -like '*Resource temporarily unavailable*' -or $Message -like '*Too many requests*') {
                    $WaitTime = Get-Random -Minimum 1.1 -Maximum 3.1
                    Write-Warning "Resource temporarily unavailable. Waiting $WaitTime seconds before retry. Attempt $($RetryCount + 1) of $maxRetries"
                    $ShouldRetry = $true
                }

                if ($ShouldRetry) {
                    $RetryCount++
                    if ($RetryCount -lt $maxRetries) {
                        Start-Sleep -Seconds $WaitTime
                    }
                } else {
                    # Not a retryable error, exit immediately
                    break
                }
            }
        } while (-not $RequestSuccessful -and $RetryCount -lt $maxRetries)

        if (($RequestSuccessful -eq $false) -and $ScheduleRetry -eq $true -and $ShouldRetry -eq $true) {
            #Create a scheduled task to retry the task later, when there is less pressure on the system, but only if ScheduledRetry is true.
            try {
                $TaskId = (New-Guid).Guid.ToString()

                # Prepare parameters for the retry
                $RetryParameters = @{
                    uri      = $uri
                    tenantid = $tenantid
                    type     = $type
                    body     = $body
                }

                # Add optional parameters if they were provided
                if ($scope) { $RetryParameters.scope = $scope }
                if ($AsApp) { $RetryParameters.AsApp = $AsApp }
                if ($NoAuthCheck) { $RetryParameters.NoAuthCheck = $NoAuthCheck }
                if ($skipTokenCache) { $RetryParameters.skipTokenCache = $skipTokenCache }
                if ($AddedHeaders) { $RetryParameters.AddedHeaders = $AddedHeaders }
                if ($contentType) { $RetryParameters.contentType = $contentType }
                if ($IgnoreErrors) { $RetryParameters.IgnoreErrors = $IgnoreErrors }
                if ($returnHeaders) { $RetryParameters.ReturnHeaders = $returnHeaders }
                if ($maxRetries) { $RetryParameters.maxRetries = $maxRetries }

                # Create the scheduled task object
                $TaskObject = [PSCustomObject]@{
                    TenantFilter  = $tenantid
                    Name          = "Graph API Retry - $($uri -replace 'https://graph.microsoft.com/(beta|v1.0)/', '')"
                    Command       = [PSCustomObject]@{ value = 'New-CIPPGraphRetry' }
                    Parameters    = $RetryParameters
                    ScheduledTime = [int64](([datetime]::UtcNow.AddMinutes(15)) - (Get-Date '1/1/1970')).TotalSeconds
                    Recurrence    = '0'
                    PostExecution = @{}
                    Reference     = "GraphRetry-$TaskId"
                }

                # Add the scheduled task (hidden = system task)
                $null = Add-CIPPScheduledTask -Task $TaskObject -Hidden $true

                return @{Result = "Scheduled job with id $TaskId as Graph API was too busy to respond. Check the job status in the scheduler." }
            } catch {
                Write-Warning "Failed to schedule retry task: $($_.Exception.Message)"
            }
        }

        if ($RequestSuccessful -eq $false) {
            throw $Message
        }

        if ($returnHeaders) {
            return $responseHeaders
        } else {
            return $ReturnedData
        }
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}
