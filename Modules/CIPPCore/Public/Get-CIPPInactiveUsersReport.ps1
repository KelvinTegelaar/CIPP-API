function Get-CIPPInactiveUsersReport {
    <#
    .SYNOPSIS
        Lists users that have not signed in for a number of days, from the CIPP Reporting database
    .PARAMETER TenantFilter
        The tenant to report on, or AllTenants
    .PARAMETER InactiveDays
        Days without a sign-in before a user counts as inactive
    .EXAMPLE
        Get-CIPPInactiveUsersReport -TenantFilter 'contoso.onmicrosoft.com' -InactiveDays 90
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [int]$InactiveDays = 180,

        # Rows already read by the AllTenants path, keyed by cache type
        [Parameter(DontShow = $true)]
        [hashtable]$DbItems
    )

    if ($TenantFilter -eq 'AllTenants') {
        $ItemsByTenant = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'Users' -ByTenant

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in @($ItemsByTenant.Keys)) {
            # Hand each tenant its rows and drop them here so they can be freed once processed
            $TenantItems = $ItemsByTenant[$Tenant]; $ItemsByTenant[$Tenant] = $null
            try {
                $TenantResults = Get-CIPPInactiveUsersReport -TenantFilter $Tenant -InactiveDays $InactiveDays -DbItems @{ Users = $TenantItems }
                foreach ($Result in $TenantResults) {
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'InactiveUsersReport' -tenant $Tenant -message "Failed to get inactive users: $($_.Exception.Message)" -sev Warning
            }
        }
        return @($AllResults)
    }

    $Lookup = (Get-Date).AddDays(-$InactiveDays).ToUniversalTime()

    # Get users from database
    $DbRequest = @{ TenantFilter = $TenantFilter; Type = 'Users' }
    if ($DbItems) { $DbRequest.Rows = $DbItems['Users'] }
    $Users = New-CIPPDbRequest @DbRequest

    if (-not $Users) {
        Write-Information "No user data found in database for tenant $TenantFilter"
        return @()
    }

    # Get tenant info for display name
    $TenantInfo = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
    $TenantDisplayName = $TenantInfo.displayName ?? $TenantFilter

    # The Users-Count row is rewritten when a cache run for this tenant completes, so its table
    # Timestamp is when this data was actually refreshed - request time must not be reported here.
    $LastRefreshed = $null
    try {
        $CountRow = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Users' -CountsOnly | Select-Object -First 1
        if ($CountRow.Timestamp) {
            $LastRefreshed = ([DateTimeOffset]$CountRow.Timestamp).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        }
    } catch {
        Write-Information "Could not determine Users cache refresh time for $($TenantFilter): $($_.Exception.Message)"
    }

    $InactiveUsers = foreach ($User in $Users) {
        # Disabled (blocked) users are kept: a dormant, already-blocked account is a cleanup
        # candidate, and the accountEnabled field below lets the report show which inactive
        # accounts are already blocked and need no further action.

        # Skip guest users
        if ($User.userType -eq 'Guest') { continue }

        # Determine last sign-in - most recent of the three signInActivity fields.
        # lastSuccessfulSignInDateTime can run ahead of the other two (it is what the Entra
        # profile blade shows); leaving it out lists recently-active users as inactive.
        $lastInteractive = $User.signInActivity.lastSignInDateTime
        $lastNonInteractive = $User.signInActivity.lastNonInteractiveSignInDateTime
        $lastSuccessful = $User.signInActivity.lastSuccessfulSignInDateTime

        $lastSignIn = $null
        foreach ($Candidate in @($lastInteractive, $lastNonInteractive, $lastSuccessful)) {
            if ($Candidate -and (-not $lastSignIn -or [DateTime]$Candidate -gt [DateTime]$lastSignIn)) {
                $lastSignIn = $Candidate
            }
        }

        # Check if user is inactive
        $isInactive = (-not $lastSignIn) -or ([DateTime]$lastSignIn -le $Lookup)

        if ($isInactive) {
            # Calculate days since last sign-in
            $daysSinceSignIn = if ($lastSignIn) {
                [Math]::Round(((Get-Date) - [DateTime]$lastSignIn).TotalDays)
            } else {
                $null
            }

            # Count assigned licenses
            $numberOfAssignedLicenses = if ($User.assignedLicenses) {
                $User.assignedLicenses.Count
            } else {
                0
            }

            [PSCustomObject]@{
                tenantId                         = $TenantFilter
                tenantDisplayName                = $TenantDisplayName
                azureAdUserId                    = $User.id
                userPrincipalName                = $User.userPrincipalName
                displayName                      = $User.displayName
                userType                         = $User.userType
                createdDateTime                  = $User.createdDateTime
                lastSignInDateTime               = $lastInteractive
                lastNonInteractiveSignInDateTime = $lastNonInteractive
                lastSuccessfulSignInDateTime     = $lastSuccessful
                lastRefreshedDateTime            = $LastRefreshed
                numberOfAssignedLicenses         = $numberOfAssignedLicenses
                daysSinceLastSignIn              = $daysSinceSignIn
                accountEnabled                   = $User.accountEnabled
            }
        }
    }

    return @($InactiveUsers)
}
