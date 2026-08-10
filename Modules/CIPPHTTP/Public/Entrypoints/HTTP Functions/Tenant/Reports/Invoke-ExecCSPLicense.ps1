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
            $DaysBefore = [int]($Request.Body.DaysBeforeRenewal ?? 3)
            if ($DaysBefore -lt 1) { $DaysBefore = 3 }

            $Subscription = Get-SherwebCurrentSubscription -TenantFilter $TenantFilter -SKU $SKU | Select-Object -First 1
            if (-not $Subscription) {
                throw "No existing subscription with SKU '$SKU' found."
            }
            $RenewalDate = $Subscription.commitmentTerm.renewalConfiguration.renewalDate
            if (-not $RenewalDate) {
                throw "The subscription '$($Subscription.productName)' does not have a renewal date, so a decrease cannot be scheduled at renewal."
            }
            $RunAt = ([datetimeoffset]$RenewalDate).UtcDateTime.AddDays(-$DaysBefore)
            if ($RunAt -le [datetime]::UtcNow) {
                throw "The renewal date ($(([datetimeoffset]$RenewalDate).ToString('yyyy-MM-dd'))) minus $DaysBefore day(s) is already in the past. Use the immediate decrease action instead."
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
            $Result = "Scheduled a decrease of $RemoveCount license(s) for '$($Subscription.productName)' on $($RunAt.ToString('yyyy-MM-dd HH:mm')) UTC, $DaysBefore day(s) before the renewal date. The decrease only executes if at least $RemoveCount license(s) are unassigned at that time."
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
