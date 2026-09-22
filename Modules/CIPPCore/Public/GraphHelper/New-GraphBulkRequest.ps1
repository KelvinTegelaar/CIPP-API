function New-GraphBulkRequest {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        $tenantid,
        $NoAuthCheck,
        $scope,
        $asapp,
        $Requests,
        $NoPaginateIds = @(),
        [ValidateSet('v1.0', 'beta')]
        $Version = 'beta',
        $Headers
    )

    if ($NoAuthCheck -or (Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        if ($Headers) {
            $Headers = $Headers
        } else {
            $Headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp
        }

        if ($script:XMsThrottlePriority) {
            $headers['x-ms-throttle-priority'] = $script:XMsThrottlePriority
        }

        $URL = "https://graph.microsoft.com/$Version/`$batch"

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
        try {
            $ReturnedData = for ($i = 0; $i -lt $Requests.count; $i += 20) {
                $req = @{}
                # Use select to create hashtables of id, method and url for each call
                $req['requests'] = ($Requests[$i..($i + 19)])
                $ReqBody = (ConvertTo-Json -InputObject $req -Compress -Depth 100)
                $Return = Invoke-CIPPRestMethod -Uri $URL -Method POST -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $ReqBody
                if ($Return.headers.'retry-after') {
                    #Revist this when we are pushing this data into our custom schema instead.
                    $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp
                    Invoke-CIPPRestMethod -Uri $URL -Method POST -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $ReqBody
                }
                $Return
            }
            foreach ($MoreData in $ReturnedData.Responses | Where-Object { $_.body.'@odata.nextLink' }) {
                if ($NoPaginateIds -contains $MoreData.id) {
                    continue
                }
                Write-Host 'Getting more'
                Write-Host $MoreData.body.'@odata.nextLink'
                # Re-batch nextLink pagination instead of sequential calls
                $NextLinkQueue = [System.Collections.Generic.Queue[PSCustomObject]]::new()
                $InitialNextUrl = $MoreData.body.'@odata.nextLink' -replace 'https://graph.microsoft.com/(v1\.0|beta)', ''
                $NextLinkQueue.Enqueue([PSCustomObject]@{
                        id  = $MoreData.id
                        url = $InitialNextUrl
                    })
                $RetriedPages = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

                while ($NextLinkQueue.Count -gt 0) {
                    # Drain up to 20 nextLinks into a batch
                    $NextBatchRequests = [System.Collections.Generic.List[PSCustomObject]]::new()
                    while ($NextLinkQueue.Count -gt 0 -and $NextBatchRequests.Count -lt 20) {
                        $Item = $NextLinkQueue.Dequeue()
                        $NextBatchRequests.Add([PSCustomObject]@{
                                id     = $Item.id
                                method = 'GET'
                                url    = $Item.url
                            })
                    }

                    $NextReqBody = ConvertTo-Json -InputObject @{ requests = @($NextBatchRequests) } -Compress -Depth 100
                    $NextReturn = Invoke-CIPPRestMethod -Uri $URL -Method POST -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $NextReqBody
                    if ($NextReturn.headers.'retry-after') {
                        $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp
                        $NextReturn = Invoke-CIPPRestMethod -Uri $URL -Method POST -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $NextReqBody
                    }

                    # A continuation page that fails (throttled, timed out, or missing from the batch
                    # reply) used to be dropped silently: the parent item kept status 200 with only
                    # its first page, so callers took a partial list for the complete one. The drift
                    # engine then pruned the decisions for every policy that sat on a later page and
                    # re-created them as New on the next run. Retry the page once, then mark the
                    # parent so callers can tell the collection is incomplete.
                    $AnsweredIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($NextResponse in $NextReturn.responses) {
                        $null = $AnsweredIds.Add([string]$NextResponse.id)
                        $PageStatus = $NextResponse.status -as [int]
                        if ($PageStatus -ge 400) {
                            $PageRequest = $NextBatchRequests | Where-Object { $_.id -eq $NextResponse.id } | Select-Object -First 1
                            $RetryKey = "$($NextResponse.id)|$($PageRequest.url)"
                            if ($PageRequest -and $RetriedPages.Add($RetryKey)) {
                                $RetryAfter = [Math]::Min([Math]::Max(($NextResponse.headers.'Retry-After' -as [int]), 0), 30)
                                if ($RetryAfter -gt 0) { Start-Sleep -Seconds $RetryAfter }
                                $NextLinkQueue.Enqueue([PSCustomObject]@{
                                        id  = $PageRequest.id
                                        url = $PageRequest.url
                                    })
                                continue
                            }
                            $PageError = "continuation page returned $PageStatus$(if ($NextResponse.body.error.message) { ": $($NextResponse.body.error.message)" })"
                            Write-Warning "Graph bulk request for '$($NextResponse.id)' ($tenantid): $PageError. The result is incomplete."
                            $MoreData | Add-Member -NotePropertyMembers ([ordered]@{
                                    PagingIncomplete = $true
                                    PagingError      = $PageError
                                }) -Force
                            continue
                        }
                        if ($NextResponse.body.value) {
                            $NewValues = [System.Collections.Generic.List[PSCustomObject]]$MoreData.body.value
                            foreach ($val in $NextResponse.body.value) { $NewValues.Add($val) }
                            $MoreData.body.value = $NewValues
                        }
                        if ($NextResponse.body.'@odata.nextLink' -and $NoPaginateIds -notcontains $NextResponse.id) {
                            $ContinueUrl = $NextResponse.body.'@odata.nextLink' -replace 'https://graph.microsoft.com/(v1\.0|beta)', ''
                            $NextLinkQueue.Enqueue([PSCustomObject]@{
                                    id  = $NextResponse.id
                                    url = $ContinueUrl
                                })
                        }
                    }
                    foreach ($Unanswered in ($NextBatchRequests | Where-Object { -not $AnsweredIds.Contains([string]$_.id) })) {
                        Write-Warning "Graph bulk request for '$($Unanswered.id)' ($tenantid): no reply for continuation page '$($Unanswered.url)'. The result is incomplete."
                        $MoreData | Add-Member -NotePropertyMembers ([ordered]@{
                                PagingIncomplete = $true
                                PagingError      = 'continuation page missing from the batch reply'
                            }) -Force
                    }
                }
            }

        } catch {
            Write-Host 'updating graph table because something failed.'
            $ErrorRecord = $_ # $_ is the parse error inside the nested catch
            # Try to parse ErrorDetails.Message as JSON
            $ErrorBody = [string]$ErrorRecord.ErrorDetails.Message
            if ($ErrorBody) {
                try {
                    $ErrorJson = $ErrorBody | ConvertFrom-Json -ErrorAction Stop
                    $Message = $ErrorJson.error.message
                } catch {
                    $Message = $ErrorBody
                }
            }

            if ([string]::IsNullOrEmpty($Message)) {
                $Message = $ErrorRecord.Exception.Message
            }

            # An IIS error page ('Request Too Long') is HTML, not a Graph error; keep its text only.
            if ($Message -match '(?i)<html') {
                $Message = ($Message -replace '(?s)<[^>]+>', ' ' -replace '\s+', ' ').Trim()
            }

            if ($Message -ne 'Request not applicable to target tenant.') {
                $Tenant.LastGraphError = $Message ?? ''
                $Tenant.GraphErrorCount++
                Update-AzDataTableEntity -Force @TenantsTable -Entity $Tenant
            }
            throw $Message
        }

        if ($Tenant.PSObject.Properties.Name -notcontains 'LastGraphError') {
            $Tenant | Add-Member -MemberType NoteProperty -Name 'LastGraphError' -Value '' -Force
        } else {
            $Tenant.LastGraphError = ''
        }
        Update-AzDataTableEntity -Force @TenantsTable -Entity $Tenant
        return $ReturnedData.responses
    } else {
        Write-Error (Get-AuthorisedRequestError -TenantID $tenantid -Context 'Graph bulk request')
    }
}
