function Invoke-CIPPBaselineActivityBasedTimeout {
    <#
    .SYNOPSIS
        ActivityBasedTimeout executor: writes the org-default idle session timeout policy.
    .DESCRIPTION
        Needs its own executor because the write is an upsert against a policy whose id is
        per tenant: PATCH the existing organization-default policy, POST a new one when
        none exists. The body nests the timeout the way the portal and Graph schema do -
        ApplicationPolicies[] with the org-wide entry keyed ApplicationId 'default'.

        Create-vs-update is decided on a LIVE read, not the cached row: a cache that
        predates a policy created by an earlier run would make every run POST and collide
        with the existing org default. The spec arrives fully rendered.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        # The read result. Unused here - the write reads live state instead.
        $Current
    )

    $Timeout = "$($Remediate.timeout)"
    if ([string]::IsNullOrWhiteSpace($Timeout)) { throw 'ActivityBasedTimeout: no timeout configured to write.' }

    $PolicyDefinition = ConvertTo-Json -Compress -Depth 10 -InputObject ([PSCustomObject]@{
            ActivityBasedTimeoutPolicy = [PSCustomObject]@{
                Version             = 1
                ApplicationPolicies = @([PSCustomObject]@{ ApplicationId = 'default'; WebSessionIdleTimeout = $Timeout })
            }
        })
    $Body = ConvertTo-Json -Compress -Depth 10 -InputObject ([PSCustomObject]@{
            definition            = @($PolicyDefinition)
            isOrganizationDefault = $true
            displayName           = 'DefaultTimeoutPolicy'
        })

    $Existing = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies' -tenantid $TenantFilter -AsApp $true |
            Where-Object { $_.isOrganizationDefault -eq $true }) | Select-Object -First 1

    if ($Existing.id) {
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies/$($Existing.id)" -type PATCH -body $Body -AsApp $true
    } else {
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies' -type POST -body $Body -AsApp $true
    }
}
