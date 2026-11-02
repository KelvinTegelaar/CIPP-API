function Set-CIPPDBCacheGuests {
    <#
    .SYNOPSIS
        Caches all guest users for a tenant

    .PARAMETER TenantFilter
        The tenant to cache guest users for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching guest users' -sev Debug

        # signInActivity is an expensive property Graph only returns when explicitly selected,
        # and only on tenants with an Entra ID P1 license. Fetch it in a separate query and
        # merge, so the main query keeps returning the full beta default property set. Each
        # row is stamped with signInLogsCapable so cache readers can tell a guest who never
        # signed in apart from a tenant whose sign-in data is unavailable.
        $SignInLogsCapable = Test-CIPPStandardLicense -StandardName 'GuestLifecycle' -TenantFilter $TenantFilter -Preset Entra -SkipLog
        $SignInActivityById = @{}
        if ($SignInLogsCapable) {
            # Graph caps the page size lower when signInActivity is selected
            $SignInRows = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=userType eq 'Guest'&`$select=id,signInActivity&`$count=true&`$top=500" -tenantid $TenantFilter -ComplexFilter
            foreach ($Row in $SignInRows) {
                if ($Row.id) { $SignInActivityById[$Row.id] = $Row.signInActivity }
            }
        }

        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=userType eq 'Guest'&`$expand=sponsors&`$top=999" -tenantid $TenantFilter -Stream |
            Select-Object -Property *,
            @{ Name = 'signInActivity'; Expression = { $SignInActivityById[$_.id] } },
            @{ Name = 'signInLogsCapable'; Expression = { $SignInLogsCapable } } |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Guests' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached guest users successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache guest users: $($_.Exception.Message)" -sev Error
    }
}
