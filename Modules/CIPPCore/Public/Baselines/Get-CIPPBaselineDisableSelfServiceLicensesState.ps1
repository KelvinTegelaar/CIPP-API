function Get-CIPPBaselineDisableSelfServiceLicensesState {
    <#
    .SYNOPSIS
        Prepare hook for DisableSelfServiceLicenses: self-service purchase posture across
        every product.
    .DESCRIPTION
        Grades three surfaces the classic graded: every self-service purchasable product
        must be Disabled (excluded product ids stay Enabled - the operator's allow-list),
        email-based subscription signup must be off, and - when trials are disabled - the
        trial autoclaim policy must be off.

        The products and autoclaim live OUTSIDE Graph (licensing.m365.microsoft.com and
        admin.microsoft.com, each with its own token scope); the cache collector already
        speaks both, and the products list requires the Billing Administrator GDAP role -
        a 403 there parks the row at No Data rather than inventing a verdict.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Products = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'SelfServicePurchaseProducts')
    if ($Products.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'SelfServicePurchaseProducts')) {
        return @{ Current = $null }
    }
    $AuthPolicy = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'AuthorizationPolicy') | Select-Object -First 1

    $Exclusions = @("$($Item.Variables.Exclusions)" -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $DisableTrials = [bool]($Item.Variables.DisableTrials -eq $true)

    $Offenders = [System.Collections.Generic.List[object]]::new()
    foreach ($Product in $Products) {
        $Id = "$($Product.productId)"
        if ($Id -eq 'autoclaim') {
            if ($DisableTrials -and "$($Product.policyValue)" -ne 'Disabled') {
                $Offenders.Add([PSCustomObject]@{ productId = 'autoclaim'; productName = 'Trial Autoclaim'; policyValue = 'Disabled' })
            }
            continue
        }
        $Desired = if ($Id -in $Exclusions) { 'Enabled' } else { 'Disabled' }
        if ("$($Product.policyValue)" -ne $Desired) {
            $Offenders.Add([PSCustomObject]@{ productId = $Id; productName = "$($Product.productName)"; policyValue = $Desired })
        }
    }
    if ($AuthPolicy -and [bool]$AuthPolicy.allowedToSignUpEmailBasedSubscriptions) {
        $Offenders.Add([PSCustomObject]@{ productId = 'allowedToSignUpEmailBasedSubscriptions'; productName = 'Email Based Subscriptions'; policyValue = 'Disabled' })
    }

    $Current = [PSCustomObject]@{
        productsOutOfPolicy = @($Offenders | ForEach-Object { "$($_.productName)" } | Sort-Object)
    }
    # Carried for the executor: each offender knows its target value and its endpoint is
    # picked by product id.
    $Current | Add-Member -NotePropertyName 'offenders' -NotePropertyValue @($Offenders)

    @{
        Expected = [PSCustomObject]@{ productsOutOfPolicy = @() }
        Current  = $Current
    }
}
