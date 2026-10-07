function Get-CIPPBaselineActivityBasedTimeoutState {
    <#
    .SYNOPSIS
        Prepare hook for ActivityBasedTimeout: normalizes the cached policy into a
        comparable { timeout } object.
    .DESCRIPTION
        The governed value sits in a JSON string INSIDE the policy JSON
        (definition[0] -> {"ActivityBasedTimeoutPolicy":{...}}), which the declarative read
        spec cannot express - the only reason this standard needs a hook at all. The
        portal/Graph schema nests the timeout under ApplicationPolicies (ApplicationId
        'default'); policies written by an early engine build put WebSessionIdleTimeout
        directly on the root, so both are read or those tenants report permanent drift.

        Expected is NOT returned: the definition's declarative expected ({ timeout:
        "%timeout%" }) renders correctly from the variable, and the engine owns it.
        A null Current is the honest 'not collected' signal - the engine triggers the
        collector, retries once, and parks the row at No Data if it is still missing.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policy = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ActivityBasedTimeoutPolicy' | Where-Object { $_ }) | Select-Object -First 1
    if ($null -eq $Policy) { return @{ Current = $null } }

    $CurrentTimeout = $(try {
            $AbtDefinition = (@($Policy.definition)[0] | ConvertFrom-Json).ActivityBasedTimeoutPolicy
            $DefaultApplicationPolicy = @($AbtDefinition.ApplicationPolicies) | Where-Object { $_.ApplicationId -eq 'default' } | Select-Object -First 1
            if (-not $DefaultApplicationPolicy) { $DefaultApplicationPolicy = @($AbtDefinition.ApplicationPolicies) | Select-Object -First 1 }
            $DefaultApplicationPolicy.WebSessionIdleTimeout ?? $AbtDefinition.WebSessionIdleTimeout
        } catch { $null })

    @{ Current = [PSCustomObject]@{ timeout = "$CurrentTimeout" } }
}
