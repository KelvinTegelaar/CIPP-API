function Invoke-ExecCSPLicense {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $Action = $Request.Body.Action
    $SKU = $Request.Body.SKU.value ?? $Request.Body.SKU

    try {
        if ($Action -eq 'Add') {
            $null = Set-SherwebSubscription -Headers $Headers -tenantFilter $TenantFilter -SKU $SKU -add $Request.Body.Add
        }

        if ($Action -eq 'Remove') {
            $null = Set-SherwebSubscription -Headers $Headers -tenantFilter $TenantFilter -SKU $SKU -remove $Request.Body.Remove
        }

        if ($Action -eq 'NewSub') {
            $null = Set-SherwebSubscription -Headers $Headers -tenantFilter $TenantFilter -SKU $SKU -Quantity $Request.Body.Quantity
        }
        if ($Action -eq 'Cancel') {
            $null = Remove-SherwebSubscription -Headers $Headers -tenantFilter $TenantFilter -SubscriptionIds $Request.Body.SubscriptionIds
        }

        if ($Action -eq 'ScheduleRemoval') {
            $RemoveCount = [int]($Request.Body.Remove ?? 1)
            if ($RemoveCount -lt 1) { $RemoveCount = 1 }
            # Committed (NCE) subscriptions can only be decreased in the first seven days of a new term,
            # so the task must run just AFTER the renewal date, never before it. Clamp to 1-6 days so it
            # always lands inside that window while giving Sherweb a day to process the renewal.
            $DaysAfter = [int]($Request.Body.DaysAfterRenewal ?? 1)
            if ($DaysAfter -lt 1) { $DaysAfter = 1 }
            if ($DaysAfter -gt 6) { $DaysAfter = 6 }

            $Subscription = Get-SherwebCurrentSubscription -TenantFilter $TenantFilter -SKU $SKU | Select-Object -First 1
            if (-not $Subscription) {
                throw "No existing subscription with SKU '$SKU' found."
            }
            $RenewalDate = $Subscription.commitmentTerm.renewalConfiguration.renewalDate
            if (-not $RenewalDate) {
                throw "The subscription '$($Subscription.productName)' does not have a renewal date, so a decrease cannot be scheduled at renewal."
            }
            # The renewal date is a calendar date (the first day of the next term); treat it as UTC midnight.
            $RenewalDay = [datetime]::SpecifyKind(([datetime]$RenewalDate).Date, [System.DateTimeKind]::Utc)
            $RunAt = $RenewalDay.AddDays($DaysAfter)
            if ($RunAt -le [datetime]::UtcNow) {
                throw "The renewal date ($($RenewalDay.ToString('yyyy-MM-dd'))) plus $DaysAfter day(s) is already in the past. If the subscription renewed less than seven days ago, use the immediate decrease action instead."
            }

            $TaskBody = [pscustomobject]@{
                TenantFilter  = $TenantFilter
                Name          = "Decrease Sherweb License at Renewal: $($Subscription.productName) (-$RemoveCount)"
                Command       = @{
                    value = 'Invoke-SherwebScheduledLicenseRemoval'
                    label = 'Invoke-SherwebScheduledLicenseRemoval'
                }
                Parameters    = [pscustomobject]@{
                    SKU    = $SKU
                    Remove = $RemoveCount
                }
                ScheduledTime = [int64]([datetimeoffset]$RunAt).ToUnixTimeSeconds()
            }
            $null = Add-CIPPScheduledTask -Task $TaskBody -hidden $false -Headers $Headers
            $Result = "Scheduled a decrease of $RemoveCount license(s) for '$($Subscription.productName)' on $($RunAt.ToString('yyyy-MM-dd HH:mm')) UTC, $DaysAfter day(s) after the renewal date of $($RenewalDay.ToString('yyyy-MM-dd')). Committed subscriptions can only be decreased in the first seven days of a new term, so the task runs just after renewal rather than before it. The decrease only executes if at least $RemoveCount license(s) are unassigned at that time."
        } else {
            $Result = 'License change executed successfully.'
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to execute license change. Error: $_"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    # If $GraphRequest is a GUID, the subscription was edited successfully, and return that it's done.
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Result
    }

}
