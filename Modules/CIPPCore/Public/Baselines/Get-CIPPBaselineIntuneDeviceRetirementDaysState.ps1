function Get-CIPPBaselineIntuneDeviceRetirementDaysState {
    <#
    .SYNOPSIS
        Prepare hook for intuneDeviceRetirementDays: the device cleanup rule's retirement
        window.
    .DESCRIPTION
        Grades the inactivity-before-retirement day count on the default cleanup rule. The
        tenant may carry several platform-scoped rules; the default all-platforms rule is
        preferred, falling back to the first - the classic read the collection unfiltered
        and compared whatever came back, which fans out to nonsense with several rules.

        A tenant with NO cleanup rule grades -1 against the configured days: not configured
        is drift, and remediation creates the rule rather than patching one. Never-collected
        stays No Data.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Rules = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ManagedDeviceCleanupRules')
    if ($Rules.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ManagedDeviceCleanupRules')) {
        return @{ Current = $null }
    }

    $Rule = @($Rules | Where-Object { "$($_.deviceCleanupRulePlatformType)" -eq 'all' }) | Select-Object -First 1
    if (-not $Rule) { $Rule = $Rules | Select-Object -First 1 }

    $Current = [PSCustomObject]@{
        deviceInactivityBeforeRetirementInDays = $(if ($null -eq $Rule.deviceInactivityBeforeRetirementInDays) { -1 } else { [int]$Rule.deviceInactivityBeforeRetirementInDays })
    }
    # Carried for the executor: patch this rule, or create one when the tenant has none.
    $Current | Add-Member -NotePropertyName 'ruleId' -NotePropertyValue $(if ($Rule.id) { "$($Rule.id)" } else { $null })

    @{
        Expected = [PSCustomObject]@{ deviceInactivityBeforeRetirementInDays = [int]"$($Item.Variables.days)" }
        Current  = $Current
    }
}
