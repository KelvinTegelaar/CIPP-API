function New-ExoBulkRequest {
    <#
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $tenantid,
        $cmdletArray,
        $useSystemMailbox,
        $Anchor,
        $NoAuthCheck,
        $Select,
        $ReturnWithCommand,
        [int]$MaxConcurrency = 1,
        [int]$TimeoutSec = 100,
        [switch]$Compliance,
        [switch]$AsApp
    )

    if ((Get-AuthorisedRequest -TenantID $tenantid) -or $NoAuthCheck -eq $True) {
        if ($Compliance.IsPresent) {
            $Resource = 'https://ps.compliance.protection.outlook.com'
        } else {
            $Resource = 'https://outlook.office365.com'
        }
        $Token = Get-GraphToken -Tenantid $tenantid -scope "$Resource/.default" -AsApp:$AsApp.IsPresent

        $Tenant = Get-Tenants -IncludeErrors | Where-Object { $_.defaultDomainName -eq $tenantid -or $_.customerId -eq $tenantid }
        $Headers = @{
            Authorization             = $Token.Authorization
            Prefer                    = 'odata.maxpagesize = 1000;odata.continue-on-error'
            'parameter-based-routing' = $true
            'X-AnchorMailbox'         = $Anchor
        }

        if ($Compliance.IsPresent) {
            # Compliance URL logic (omitted for brevity)
        }

        try {
            if ($Select) { $Select = "`$select=$Select" }
            $URL = "$Resource/adminapi/beta/$($Tenant.customerId)/InvokeCommand?$Select"
            $BatchURL = "$Resource/adminapi/beta/$($Tenant.customerId)/`$batch"

            # Initialize the ID to Cmdlet Name mapping
            $IdToCmdletName = @{}
            $IdToOperationGuid = @{}  # Track operation GUIDs when provided
            $IdToBatchRequest = @{}   # Original sub-requests, reused for nextLink continuations

            # Split the cmdletArray into batches of 10
            $batches = [System.Collections.Generic.List[object]]::new()
            for ($i = 0; $i -lt $cmdletArray.Length; $i += 10) {
                $batches.Add($cmdletArray[$i..[math]::Min($i + 9, $cmdletArray.Length - 1)])
            }

            $ReturnedData = [System.Collections.Generic.List[object]]::new()
            $BatchPayloads = [System.Collections.Generic.List[object]]::new()
            foreach ($batch in $batches) {
                $BatchBodyObj = @{
                    requests = @()
                }
                foreach ($cmd in $batch) {
                    $cmdparams = $cmd.CmdletInput.Parameters
                    if ($cmdparams.Identity) { $Anchor = $cmdparams.Identity }
                    if ($cmdparams.anr) { $Anchor = $cmdparams.anr }
                    if ($cmdparams.User) { $Anchor = $cmdparams.User }
                    if (!$Anchor -or $useSystemMailbox) {
                        $OnMicrosoft = $Tenant.initialDomainName
                        $Anchor = "UPN:SystemMailbox{8cc370d3-822a-4ab8-a926-bb94bd0641a9}@$($OnMicrosoft)"
                    }
                    $Headers['X-AnchorMailbox'] = "APP:SystemMailbox{bb558c35-97f1-4cb9-8ff7-d53741dc928c}@$($tenant.customerId)"
                    $Headers['X-CmdletName'] = $cmd.CmdletInput.CmdletName
                    $Headers['Accept'] = 'application/json; odata.metadata=minimal'
                    $Headers['Accept-Encoding'] = 'gzip'

                    # Use provided OperationGuid if available, otherwise generate one
                    $RequestId = if ($cmd.OperationGuid) {
                        $cmd.OperationGuid
                    } else {
                        [Guid]::NewGuid().ToString()
                    }

                    # Create clean cmdlet object for API (without OperationGuid)
                    $CleanCmd = @{
                        CmdletInput = $cmd.CmdletInput
                    }

                    $BatchRequest = @{
                        url     = $URL
                        method  = 'POST'
                        body    = $CleanCmd
                        headers = $Headers.Clone()
                        id      = $RequestId
                    }
                    $BatchBodyObj['requests'] = $BatchBodyObj['requests'] + $BatchRequest

                    # Map the Request ID to the Cmdlet Name and Operation GUID (if provided)
                    $IdToCmdletName[$RequestId] = $cmd.CmdletInput.CmdletName
                    $IdToBatchRequest[$RequestId] = $BatchRequest
                    if ($cmd.OperationGuid) {
                        $IdToOperationGuid[$RequestId] = $cmd.OperationGuid
                    }
                }
                $BatchBodyJson = ConvertTo-Json -InputObject $BatchBodyObj -Depth 10
                $BatchBodyJson = Get-CIPPTextReplacement -TenantFilter $tenantid -Text $BatchBodyJson
                # Clone the headers as they stood for this batch's POST (X-AnchorMailbox/X-CmdletName are
                # mutated per sub-request above); the $batch envelope also carries per-request headers.
                $BatchPayloads.Add(@{ Json = $BatchBodyJson; Headers = $Headers.Clone() })
            }

            # Dispatch a set of batch payloads and return the flattened sub-responses. -MaxConcurrency 1
            # (default) keeps the sequential Invoke-CIPPRestMethod loop; >1 fans out via
            # CIPP.CIPPRestClient.SendConcurrent, which bounds concurrency and retries a fully-429'd/5xx
            # POST honouring Retry-After (its backoff is separate from the per-request -TimeoutSec, so a
            # rate-limit wait never trips the timeout). EXO caps each $batch at 10 sub-requests.
            function Send-BatchPayloadSet {
                param($Payloads, $DispatchUrl, $Concurrency, $Timeout)
                $Out = [System.Collections.Generic.List[object]]::new()
                if ($Concurrency -gt 1 -and @($Payloads).Count -gt 1) {
                    $ConcRequests = [System.Collections.Generic.List[CIPP.CIPPConcurrentRequest]]::new()
                    foreach ($Payload in $Payloads) {
                        $ConcRequest = [CIPP.CIPPConcurrentRequest]::new()
                        $ConcRequest.Uri = $DispatchUrl
                        $ConcRequest.Method = 'POST'
                        $ConcRequest.Body = $Payload.Json
                        $ConcRequest.ContentType = 'application/json; charset=utf-8'
                        $ConcRequest.TimeoutSec = $Timeout
                        $ConcHeaders = [System.Collections.Generic.Dictionary[string, string]]::new()
                        foreach ($HeaderKey in $Payload.Headers.Keys) { $ConcHeaders[$HeaderKey] = [string]$Payload.Headers[$HeaderKey] }
                        $ConcRequest.Headers = $ConcHeaders
                        $ConcRequests.Add($ConcRequest)
                    }
                    foreach ($ConcResult in [CIPP.CIPPRestClient]::SendConcurrent($ConcRequests, $Concurrency, 3)) {
                        if ($ConcResult.Error) {
                            Write-Host "EXO bulk batch failed after $($ConcResult.Attempts) attempt(s): $($ConcResult.Error)"
                            continue
                        }
                        try {
                            $Parsed = $ConcResult.Result.Content | ConvertFrom-Json
                        } catch {
                            Write-Host "EXO bulk batch: could not parse response (HTTP $($ConcResult.StatusCode))"
                            continue
                        }
                        foreach ($Response in $Parsed.responses) { $Out.Add($Response) }
                    }
                } else {
                    foreach ($Payload in $Payloads) {
                        $Results = Invoke-CIPPRestMethod $DispatchUrl -ResponseHeadersVariable responseHeaders -Method POST -Body $Payload.Json -Headers $Payload.Headers -ContentType 'application/json; charset=utf-8' -TimeoutSec $Timeout
                        foreach ($Response in $Results.responses) { $Out.Add($Response) }
                    }
                }
                return $Out
            }

            foreach ($Response in (Send-BatchPayloadSet $BatchPayloads $BatchURL $MaxConcurrency $TimeoutSec)) { $ReturnedData.Add($Response) }

            # EXO can throttle individual sub-requests inside a 200 batch envelope (status 429 per response,
            # emitted under Prefer: odata.continue-on-error). SendConcurrent only sees the outer 200, so
            # retry those here: rebuild the throttled sub-requests into fresh batches, honour Retry-After
            # (else a capped exponential backoff), and swap the successful results back in by id.
            $RateLimitRetry = 0
            while ($RateLimitRetry -lt 3) {
                $Throttled = @($ReturnedData | Where-Object { $_.status -eq 429 -and $_.id -and $IdToBatchRequest.ContainsKey($_.id) })
                if ($Throttled.Count -eq 0) { break }
                $RateLimitRetry++
                $RetryAfter = 0
                foreach ($ThrottledResponse in $Throttled) { $Ra = $ThrottledResponse.headers.'Retry-After' -as [int]; if ($Ra -gt $RetryAfter) { $RetryAfter = $Ra } }
                if ($RetryAfter -le 0) { $RetryAfter = [int][math]::Pow(2, $RateLimitRetry) }  # 2s, 4s, 8s
                Start-Sleep -Seconds $RetryAfter

                $ThrottledRequests = @($Throttled | ForEach-Object { $IdToBatchRequest[$_.id] })
                $RetryPayloads = [System.Collections.Generic.List[object]]::new()
                for ($i = 0; $i -lt $ThrottledRequests.Count; $i += 10) {
                    $Slice = $ThrottledRequests[$i..[math]::Min($i + 9, $ThrottledRequests.Count - 1)]
                    $RetryJson = ConvertTo-Json -InputObject @{ requests = @($Slice) } -Depth 10
                    $RetryJson = Get-CIPPTextReplacement -TenantFilter $tenantid -Text $RetryJson
                    $RetryPayloads.Add(@{ Json = $RetryJson; Headers = $Headers.Clone() })
                }

                $Replacements = @{}
                foreach ($Response in (Send-BatchPayloadSet $RetryPayloads $BatchURL $MaxConcurrency $TimeoutSec)) { if ($Response.id) { $Replacements[$Response.id] = $Response } }
                for ($i = 0; $i -lt $ReturnedData.Count; $i++) {
                    if ($ReturnedData[$i].id -and $Replacements.ContainsKey($ReturnedData[$i].id)) { $ReturnedData[$i] = $Replacements[$ReturnedData[$i].id] }
                }
            }

            # Follow @odata.nextLink continuations so results are not capped at one page (mirrors New-GraphBulkRequest).
            # The EXO admin API pages by re-POSTing the same CmdletInput body to the nextLink URL.
            $IdToResponse = @{}
            $NextLinkQueue = [System.Collections.Generic.Queue[object]]::new()
            foreach ($Response in $ReturnedData) {
                if ($Response.id -and -not $IdToResponse.ContainsKey($Response.id)) {
                    $IdToResponse[$Response.id] = $Response
                }
                if ($Response.body.'@odata.nextLink' -and $IdToBatchRequest.ContainsKey($Response.id)) {
                    $NextLinkQueue.Enqueue(@{ id = $Response.id; url = $Response.body.'@odata.nextLink' })
                }
            }

            while ($NextLinkQueue.Count -gt 0) {
                # Drain up to 10 nextLinks into a single $batch, same size as the main loop
                $NextBatchRequests = [System.Collections.Generic.List[object]]::new()
                while ($NextLinkQueue.Count -gt 0 -and $NextBatchRequests.Count -lt 10) {
                    $Item = $NextLinkQueue.Dequeue()
                    $ContinuationRequest = $IdToBatchRequest[$Item.id].Clone()
                    $ContinuationRequest['url'] = $Item.url
                    $NextBatchRequests.Add($ContinuationRequest)
                }

                Write-Host "Fetching next page for $($NextBatchRequests.Count) request(s)"
                $NextBatchBodyJson = ConvertTo-Json -InputObject @{ requests = @($NextBatchRequests) } -Depth 10
                $NextBatchBodyJson = Get-CIPPTextReplacement -TenantFilter $tenantid -Text $NextBatchBodyJson
                $NextResults = Invoke-CIPPRestMethod $BatchURL -Method POST -Body $NextBatchBodyJson -Headers $Headers -ContentType 'application/json; charset=utf-8'

                foreach ($NextResponse in $NextResults.responses) {
                    $OriginalResponse = $IdToResponse[$NextResponse.id]
                    if (-not $OriginalResponse) { continue }
                    if ($NextResponse.body.value) {
                        $MergedValues = [System.Collections.Generic.List[object]]::new()
                        foreach ($val in @($OriginalResponse.body.value)) { $MergedValues.Add($val) }
                        foreach ($val in @($NextResponse.body.value)) { $MergedValues.Add($val) }
                        $OriginalResponse.body.value = $MergedValues
                    }
                    if ($NextResponse.body.'@odata.nextLink') {
                        $NextLinkQueue.Enqueue(@{ id = $NextResponse.id; url = $NextResponse.body.'@odata.nextLink' })
                    }
                }
            }
        } catch {
            # Error handling (omitted for brevity)
        }

        #Write-Information ($responseHeaders | ConvertTo-Json -Depth 10)

        # Process the returned data
        if ($ReturnWithCommand) {
            $FinalData = @{}
            foreach ($item in $ReturnedData) {
                $itemId = $item.id
                $CmdletName = $IdToCmdletName[$itemId]
                $OperationGuid = $IdToOperationGuid[$itemId]  # Will be $null if not provided
                $body = $item.body.PSObject.Copy()

                if ($body.'@adminapi.warnings') {
                    Write-Warning ($body.'@adminapi.warnings' | Out-String)
                }
                if (![string]::IsNullOrEmpty($body.error.details.message) -or ![string]::IsNullOrEmpty($body.error.message)) {
                    if ($body.error.details.message) {
                        $msg = [pscustomobject]@{ error = $body.error.details.message; target = $body.error.details.target }
                    } else {
                        $msg = [pscustomobject]@{ error = $body.error.message; target = $body.error.details.target }
                    }

                    # Add OperationGuid to error if it was provided
                    if ($OperationGuid) {
                        $msg | Add-Member -MemberType NoteProperty -Name 'OperationGuid' -Value $OperationGuid -Force
                    }

                    $body | Add-Member -MemberType NoteProperty -Name 'value' -Value $msg -Force
                } else {
                    # Handle successful operations - add OperationGuid if provided
                    if ($body.value) {
                        # Add GUID to existing results if provided
                        if ($OperationGuid) {
                            if ($body.value -is [array]) {
                                foreach ($val in $body.value) {
                                    $val | Add-Member -MemberType NoteProperty -Name 'OperationGuid' -Value $OperationGuid -Force
                                }
                            } else {
                                $body.value | Add-Member -MemberType NoteProperty -Name 'OperationGuid' -Value $OperationGuid -Force
                            }
                        }
                    } else {
                        # Create success indicators when GUID was provided (caller wants tracking)
                        if ($OperationGuid) {
                            $body | Add-Member -MemberType NoteProperty -Name 'value' -Value ([pscustomobject]@{
                                Success = $true
                                OperationGuid = $OperationGuid
                            }) -Force
                        }
                    }
                }

                $resultValues = $body.value
                foreach ($resultValue in $resultValues) {
                    if (-not $FinalData.ContainsKey($CmdletName)) {
                        $FinalData[$CmdletName] = [System.Collections.Generic.List[object]]::new()
                        $FinalData[$CmdletName].Add($resultValue)
                    } else {
                        $FinalData[$CmdletName].Add($resultValue)
                    }
                }
            }
        } else {
            $FinalData = foreach ($item in $ReturnedData) {
                $OperationGuid = $IdToOperationGuid[$item.id]  # Will be $null if not provided
                $body = $item.body.PSObject.Copy()

                if ($body.'@adminapi.warnings') {
                    Write-Warning ($body.'@adminapi.warnings' | Out-String)
                }
                if (![string]::IsNullOrEmpty($body.error.details.message) -or ![string]::IsNullOrEmpty($body.error.message)) {
                    if ($body.error.details.message) {
                        $msg = [pscustomobject]@{ error = $body.error.details.message; target = $body.error.details.target }
                    } else {
                        $msg = [pscustomobject]@{ error = $body.error.message; target = $body.error.details.target }
                    }

                    # Add OperationGuid to error if it was provided
                    if ($OperationGuid) {
                        $msg | Add-Member -MemberType NoteProperty -Name 'OperationGuid' -Value $OperationGuid -Force
                    }

                    $body | Add-Member -MemberType NoteProperty -Name 'value' -Value $msg -Force
                } else {
                    # Handle successful operations
                    if ($body.value) {
                        # Add GUID to existing results if provided
                        if ($OperationGuid) {
                            if ($body.value -is [array]) {
                                foreach ($val in $body.value) {
                                    $val | Add-Member -MemberType NoteProperty -Name 'OperationGuid' -Value $OperationGuid -Force
                                }
                            } else {
                                $body.value | Add-Member -MemberType NoteProperty -Name 'OperationGuid' -Value $OperationGuid -Force
                            }
                        }
                    } else {
                        # Create success indicators when GUID was provided (caller wants tracking)
                        if ($OperationGuid) {
                            $body | Add-Member -MemberType NoteProperty -Name 'value' -Value ([pscustomobject]@{
                                Success = $true
                                OperationGuid = $OperationGuid
                            }) -Force
                        }
                    }
                }
                $body.value
            }
        }
        return $FinalData

    } else {
        Write-Error (Get-AuthorisedRequestError -TenantID $tenantid -Context 'Exchange bulk request')
    }
}
