function Invoke-SherwebScheduledLicenseRemoval {
    <#
    .SYNOPSIS
        Decreases a Sherweb subscription quantity, but only when unassigned licenses are available.

    .DESCRIPTION
        Designed to run as a scheduled task shortly before a subscription's renewal date (inside
        the cancellation window). Checks the actual license assignment state in the tenant first:
        the Sherweb product is matched to its Microsoft 365 SKU by product name via the cached
        license overview, and live assignment counts come from Graph subscribedSkus. The decrease
        only executes when at least the requested number of licenses is unassigned; otherwise the
        task completes with a skip message and changes nothing.

    .PARAMETER TenantFilter
        The tenant the subscription belongs to. Supplied by the scheduler.

    .PARAMETER SKU
        The Sherweb subscription SKU to decrease.

    .PARAMETER Remove
        The number of licenses to remove. Defaults to 1.

    .PARAMETER Headers
        Optional headers for logging context. Supplied by the scheduler.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$SKU,

        [int]$Remove = 1,

        $Headers
    )

    try {
        $Subscription = Get-SherwebCurrentSubscription -TenantFilter $TenantFilter -SKU $SKU | Select-Object -First 1
        if (-not $Subscription) {
            $Result = "Scheduled license decrease skipped: no Sherweb subscription with SKU '$SKU' exists anymore for $TenantFilter."
            Write-LogMessage -API 'Scheduler_Sherweb' -tenant $TenantFilter -message $Result -sev Warning
            return $Result
        }
        $ProductName = $Subscription.productName

        # Match the Sherweb product to its Microsoft 365 SKU by display name via the cached
        # license overview. If the product cannot be matched unambiguously, do nothing - a
        # wrong-SKU decrease is worse than a skipped one.
        $LicenseOverview = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'LicenseOverview')
        $Matched = @($LicenseOverview | Where-Object { $_.License -eq $ProductName })
        if ($Matched.Count -eq 0) {
            $Matched = @($LicenseOverview | Where-Object { $_.License -and ($_.License -like "*$ProductName*" -or $ProductName -like "*$($_.License)*") })
        }
        if ($Matched.Count -ne 1) {
            $Result = "Scheduled license decrease skipped for '$ProductName' ($SKU): could not unambiguously match the product to a Microsoft 365 SKU (found $($Matched.Count) matches in the license overview), so the unassigned license check cannot be performed. No changes were made."
            Write-LogMessage -API 'Scheduler_Sherweb' -tenant $TenantFilter -message $Result -sev Warning
            return $Result
        }
        $SkuId = $Matched[0].skuId

        # Live assignment state - the decrease must only happen when licenses are actually free
        $SubscribedSkus = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $TenantFilter
        $GraphSku = $SubscribedSkus | Where-Object { $_.skuId -eq $SkuId } | Select-Object -First 1
        if (-not $GraphSku) {
            $Result = "Scheduled license decrease skipped for '$ProductName' ($SKU): the matched SKU $SkuId was not found in the tenant's subscribed SKUs. No changes were made."
            Write-LogMessage -API 'Scheduler_Sherweb' -tenant $TenantFilter -message $Result -sev Warning
            return $Result
        }

        $Unassigned = [int]$GraphSku.prepaidUnits.enabled - [int]$GraphSku.consumedUnits
        if ($Unassigned -lt $Remove) {
            $Result = "Scheduled license decrease skipped for '$ProductName' ($SKU): $Remove license(s) should be removed but only $Unassigned are unassigned ($($GraphSku.consumedUnits) of $($GraphSku.prepaidUnits.enabled) assigned). No changes were made."
            Write-LogMessage -API 'Scheduler_Sherweb' -tenant $TenantFilter -message $Result -sev Info
            return $Result
        }

        $null = Set-SherwebSubscription -TenantFilter $TenantFilter -SKU $SKU -Remove $Remove
        $Result = "Decreased Sherweb subscription '$ProductName' ($SKU) by $Remove license(s) to $($Subscription.quantity - $Remove). $Unassigned license(s) were unassigned at execution time."
        Write-LogMessage -API 'Scheduler_Sherweb' -tenant $TenantFilter -message $Result -sev Info
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Scheduled license decrease failed for SKU '$SKU': $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API 'Scheduler_Sherweb' -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        throw $Result
    }
}
