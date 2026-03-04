function Get-CIPPAlertInactiveLicensedUsers {
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

            if ($InputValue -is [hashtable] -or $InputValue -is [pscustomobject]) {
                $excludeDisabled = [bool]$InputValue.ExcludeDisabled
                if ($null -ne $InputValue.DaysSinceLastLogin -and $InputValue.DaysSinceLastLogin -ne '') {
                    $parsedDays = 0
                    if ([int]::TryParse($InputValue.DaysSinceLastLogin.ToString(), [ref]$parsedDays) -and $parsedDays -gt 0) {
                        $inactiveDays = $parsedDays
                    }
                }
            } elseif ($InputValue -eq $true) {
                # Backwards compatibility: legacy single-input boolean means exclude disabled users
                $excludeDisabled = $true
            }

            $Lookup = (Get-Date).AddDays(-$inactiveDays).ToUniversalTime()
            Write-Host "Checking for users inactive since $Lookup (excluding disabled: $excludeDisabled)"
            # Build base filter - cannot filter assignedLicenses server-side
            $BaseFilter = if ($excludeDisabled) { 'accountEnabled eq true' } else { '' }

            $Uri = if ($BaseFilter) {
                "https://graph.microsoft.com/beta/users?`$filter=$BaseFilter&`$select=id,UserPrincipalName,signInActivity,mail,userType,accountEnabled,assignedLicenses"
            } else {
                "https://graph.microsoft.com/beta/users?`$select=id,UserPrincipalName,signInActivity,mail,userType,accountEnabled,assignedLicenses"
            }

            $GraphRequest = New-GraphGetRequest -uri $Uri -scope 'https://graph.microsoft.com/.default' -tenantid $TenantFilter |
                Where-Object { $null -ne $_.assignedLicenses -and $_.assignedLicenses.Count -gt 0 }

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
                        $Message = 'User {0} has never signed in but still has a license assigned.' -f $user.UserPrincipalName
                    } else {
                        $daysSinceSignIn = [Math]::Round(((Get-Date) - [DateTime]$lastSignIn).TotalDays)
                        $Message = 'User {0} has been inactive for {1} days but still has a license assigned. Last sign-in: {2}' -f $user.UserPrincipalName, $daysSinceSignIn, $lastSignIn
                    }

                    [PSCustomObject]@{
                        UserPrincipalName = $user.UserPrincipalName
                        Id                = $user.id
                        lastSignIn        = $lastSignIn
                        Message           = $Message
                        Tenant            = $TenantFilter
                    }
                }
            }

            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        } catch {}
    } catch {
        Write-LogMessage -API 'Alerts' -tenant $($TenantFilter) -message "Failed to check inactive users with licenses for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)" -sev Error
    }
}
