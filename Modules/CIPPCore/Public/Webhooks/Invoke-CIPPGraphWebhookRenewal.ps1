function Invoke-CippGraphWebhookRenewal {
    $StartTime = Get-Date
    $MaxExecutionMinutes = 8  # Leave buffer before 10-minute timeout
    $RenewalDate = (Get-Date).AddDays(1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $body = @{
        'expirationDateTime' = "$RenewalDate"
    } | ConvertTo-Json

    $Tenants = Get-Tenants -IncludeErrors
    # Use hashtables for O(1) lookup instead of O(n) array search
    $TenantDomainsHash = @{}
    $TenantCustomerIdsHash = @{}
    foreach ($Tenant in $Tenants) {
        if ($Tenant.defaultDomainName) { $TenantDomainsHash[$Tenant.defaultDomainName] = $true }
        if ($Tenant.customerId) { $TenantCustomerIdsHash[$Tenant.customerId] = $true }
    }

    $WebhookTable = Get-CIPPTable -TableName webhookTable
    try {
        # Use server-side filter for non-empty SubscriptionID, then filter expiration client-side
        # (Date comparisons in Azure Table filters are limited)
        $ExpirationCutoff = (Get-Date).AddHours(2)
        $WebhookData = Get-AzDataTableEntity @WebhookTable -Filter "SubscriptionID ne ''" | 
            Where-Object { $null -ne $_.SubscriptionID -and ((Get-Date($_.Expiration)) -le $ExpirationCutoff) }
    } catch {
        $WebhookData = @()
    }

    $WebhookCount = ($WebhookData | Measure-Object).Count
    if ($WebhookCount -gt 0) {
        Write-LogMessage -API 'Scheduler_RenewGraphSubscriptions' -tenant 'none' -message "Starting Graph Subscription Renewal for $WebhookCount webhooks" -sev Info

        # First pass: Filter out invalid tenants (sequential - fast operation)
        $ValidWebhooks = [System.Collections.Generic.List[object]]::new()
        $SkippedCount = 0
        foreach ($UpdateSub in $WebhookData) {
            $TenantFilter = $UpdateSub.PartitionKey
            if (-not $TenantDomainsHash.ContainsKey($TenantFilter) -and -not $TenantCustomerIdsHash.ContainsKey($TenantFilter)) {
                Write-LogMessage -API 'Renew_Graph_Subscriptions' -message "Removing Subscription Renewal for $($UpdateSub.SubscriptionID) as tenant $TenantFilter is not in the tenant list." -Sev 'Warning' -tenant $TenantFilter
                try {
                    Remove-CIPPAzDataTableEntity -Force @WebhookTable -Entity $UpdateSub -ErrorAction Stop
                } catch {
                    if ($_.Exception.Message -notmatch 'does not exist|ResourceNotFound') {
                        Write-Warning "Failed to remove entity: $($_.Exception.Message)"
                    }
                }
                $SkippedCount++
            } else {
                $ValidWebhooks.Add($UpdateSub)
            }
        }

        $BatchSize = 10
        $ThrottleLimit = 10
        $ProcessedCount = 0
        $SuccessCount = 0
        $FailedCount = 0

        for ($i = 0; $i -lt $ValidWebhooks.Count; $i += $BatchSize) {
            $ElapsedMinutes = ((Get-Date) - $StartTime).TotalMinutes
            if ($ElapsedMinutes -ge $MaxExecutionMinutes) {
                $RemainingCount = $ValidWebhooks.Count - $ProcessedCount
                Write-LogMessage -API 'Scheduler_RenewGraphSubscriptions' -tenant 'none' -message "Stopping webhook renewal after $ProcessedCount of $($ValidWebhooks.Count) - approaching timeout. $RemainingCount webhooks will be processed in next run." -sev Warning
                break
            }

            $EndIndex = [Math]::Min($i + $BatchSize - 1, $ValidWebhooks.Count - 1)
            $CurrentBatch = $ValidWebhooks[$i..$EndIndex]

            $Results = $CurrentBatch | ForEach-Object -Parallel {
                $UpdateSub = $_
                $RenewalDate = $using:RenewalDate
                $body = $using:body
                $WebhookTable = $using:WebhookTable

                try {
                    Import-Module CIPPCore -Force
                    Import-Module AzBobbyTables -Force -ErrorAction SilentlyContinue
                } catch {
                    Write-Warning "Failed to import modules in parallel runspace: $($_.Exception.Message)"
                }

                $Result = @{
                    Success = $false
                    SubscriptionID = $UpdateSub.SubscriptionID
                    TenantFilter = $UpdateSub.PartitionKey
                    Error = $null
                }

                try {
                    $TenantFilter = $UpdateSub.PartitionKey

                    try {
                        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/subscriptions/$($UpdateSub.SubscriptionID)" -tenantid $TenantFilter -type PATCH -body $body
                        $UpdateSub.Expiration = $RenewalDate
                        $null = Add-AzDataTableEntity @WebhookTable -Entity $UpdateSub -Force
                        $Result.Success = $true
                    } catch {
                        # Renewal failed - try to recreate
                        $BaseURL = "$(([uri]($UpdateSub.WebhookNotificationUrl)).Host)"
                        $TypeofSubscription = if ($UpdateSub.TypeofSubscription) { "$($UpdateSub.TypeofSubscription)" } else { 'updated' }
                        $Resource = "$($UpdateSub.Resource)"
                        $EventType = "$($UpdateSub.EventType)"

                        Write-Information "Recreating: $($UpdateSub.SubscriptionID) as renewal failed for $TenantFilter"
                        $CreateResult = New-CIPPGraphSubscription -TenantFilter $TenantFilter -TypeofSubscription $TypeofSubscription -BaseURL $BaseURL -Resource $Resource -EventType $EventType -Headers 'GraphSubscriptionRenewal' -Recreate

                        if ($CreateResult -match 'Created Webhook subscription for') {
                            try {
                                Remove-CIPPAzDataTableEntity -Force @WebhookTable -Entity $UpdateSub -ErrorAction Stop
                            } catch {
                                if ($_.Exception.Message -notmatch 'does not exist|ResourceNotFound') {
                                    throw
                                }
                            }
                            $Result.Success = $true
                        } else {
                            $Result.Error = "Recreation failed: $CreateResult"
                        }
                    }
                } catch {
                    $Result.Error = $_.Exception.Message
                }

                $Result
            } -ThrottleLimit $ThrottleLimit

            # Aggregate results
            foreach ($Result in $Results) {
                $ProcessedCount++
                if ($Result.Success) {
                    $SuccessCount++
                } else {
                    $FailedCount++
                    if ($Result.Error) {
                        Write-LogMessage -API 'Renew_Graph_Subscriptions' -message "Failed to renew Webhook Subscription: $($Result.SubscriptionID). Error: $($Result.Error)" -Sev 'Error' -tenant $Result.TenantFilter
                    }
                }
            }

            # Log progress every batch
            if ($ProcessedCount % 50 -lt $BatchSize) {
                $ElapsedMinutes = [math]::Round(((Get-Date) - $StartTime).TotalMinutes, 2)
                Write-LogMessage -API 'Scheduler_RenewGraphSubscriptions' -tenant 'none' -message "Webhook renewal progress: $ProcessedCount/$($ValidWebhooks.Count) processed in $ElapsedMinutes minutes" -sev Info
            }
        }

        $TotalElapsed = [math]::Round(((Get-Date) - $StartTime).TotalMinutes, 2)
        Write-LogMessage -API 'Scheduler_RenewGraphSubscriptions' -tenant 'none' -message "Completed Graph Subscription Renewal: $SuccessCount succeeded, $FailedCount failed, $SkippedCount skipped out of $ProcessedCount processed in $TotalElapsed minutes" -sev Info
    }
}
