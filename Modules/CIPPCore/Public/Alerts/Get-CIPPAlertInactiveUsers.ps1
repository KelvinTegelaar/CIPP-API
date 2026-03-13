function Get-CIPPAlertInactiveUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        [Parameter(Mandatory = $false)]
        [switch]$IncludeNeverSignedIn, # Include users who have never signed in (default is to skip them), future use would allow this to be set in an alert configuration
        $TenantFilter
    )

    try {
        try {
            $inactiveDays = 90
            $excludeDisabled = $false

            $excludeDisabled = [bool]$InputValue.ExcludeDisabled
            if ($null -ne $InputValue.DaysSinceLastLogin -and $InputValue.DaysSinceLastLogin -ne '') {
                $parsedDays = 0
                if ([int]::TryParse($InputValue.DaysSinceLastLogin.ToString(), [ref]$parsedDays) -and $parsedDays -gt 0) {
                    $inactiveDays = $parsedDays
                }
            }

            $Lookup = (Get-Date).AddDays(-$inactiveDays).ToUniversalTime()
            Write-Host "Checking for users inactive since $Lookup (excluding disabled: $excludeDisabled)"
            # Build base filter - cannot filter accountEnabled server-side
            $BaseFilter = if ($excludeDisabled) { 'accountEnabled eq true' } else { '' }

            $Uri = if ($BaseFilter) {
                "https://graph.microsoft.com/beta/users?`$filter=$BaseFilter&`$select=id,UserPrincipalName,signInActivity,mail,userType,accountEnabled,assignedLicenses"
            } else {
                "https://graph.microsoft.com/beta/users?`$select=id,UserPrincipalName,signInActivity,mail,userType,accountEnabled,assignedLicenses"
            }

            $GraphRequest = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter | Where-Object { $_.userType -eq 'Member' }

            $AlertData = foreach ($user in $GraphRequest) {
                $lastInteractive = $user.signInActivity.lastSignInDateTime
                $lastNonInteractive = $user.signInActivity.lastNonInteractiveSignInDateTime

                # Find most recent sign-in
                $lastSignIn = $null
                if ($lastInteractive -and $lastNonInteractive) {
                    $lastSignIn = if ([DateTime]$lastInteractive -gt [DateTime]$lastNonInteractive) { $lastInteractive } else { $lastNonInteractive }
                } elseif ($lastInteractive) {
                    $lastSignIn = $lastInteractive
                } elseif ($lastNonInteractive) {
                    $lastSignIn = $lastNonInteractive
                }

                # Check if inactive
                $isInactive = (-not $lastSignIn) -or ([DateTime]$lastSignIn -le $Lookup)
                # Skip users who have never signed in by default (unless IncludeNeverSignedIn is specified)
                if (-not $IncludeNeverSignedIn -and -not $lastSignIn) { continue }
                # Only process inactive users
                if ($isInactive) {
                    if (-not $lastSignIn) {
                        $Message = 'User {0} has never signed in.' -f $user.UserPrincipalName
                    } else {
                        $daysSinceSignIn = [Math]::Round(((Get-Date) - [DateTime]$lastSignIn).TotalDays)
                        $Message = 'User {0} has been inactive for {1} days. Last sign-in: {2}' -f $user.UserPrincipalName, $daysSinceSignIn, $lastSignIn
                    }

                    [PSCustomObject]@{
                        UserPrincipalName   = $user.UserPrincipalName
                        Id                  = $user.id
                        lastSignIn          = $lastSignIn
                        DaysSinceLastSignIn = if ($daysSinceSignIn) { $daysSinceSignIn } else { 'N/A' }
                        Message             = $Message
                        Tenant              = $TenantFilter
                    }
                }
            }

            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        } catch {}
    } catch {
        Write-LogMessage -API 'Alerts' -tenant $($TenantFilter) -message "Failed to check inactive users with licenses for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)" -sev Error
    }
}
