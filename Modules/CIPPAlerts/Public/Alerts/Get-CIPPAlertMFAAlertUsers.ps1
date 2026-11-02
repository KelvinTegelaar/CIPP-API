function Get-CIPPAlertMFAAlertUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        Write-Host "Checking MFA status for users in tenant '$TenantFilter'..."
        $MFAReport = try { Get-CIPPMFAStateReport -TenantFilter $TenantFilter | Where-Object { $_.DisplayName -ne 'On-Premises Directory Synchronization Service Account' } } catch { Write-Host "Could not get cached report for tenant '$TenantFilter' $_" }

        $Users = if ($MFAReport) {
            $MFAReport | Where-Object { $_.IsAdmin -ne $true -and $_.MFARegistration -eq $false -and $_.UserType -ne 'Guest' -and $_.UPN -notmatch '^package_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@' }
        } else {
            New-GraphGETRequest -uri "https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?`$top=999&filter=IsAdmin eq false and isMfaRegistered eq false and userType eq 'member'&`$select=userDisplayName,userPrincipalName,lastUpdatedDateTime,isMfaRegistered,IsAdmin" -tenantid $($TenantFilter) -AsApp $true |
            Where-Object { $_.userDisplayName -ne 'On-Premises Directory Synchronization Service Account' -and $_.userPrincipalName -notmatch '^package_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@' } |
            Select-Object @{n = 'UPN'; e = { $_.userPrincipalName } }, @{n = 'DisplayName'; e = { $_.userDisplayName } }
        }

        # Give new accounts a grace period to register MFA before they are alerted on.
        # Only suppress when we positively know createdDateTime is within the window;
        # unknown age (missing user) leaves them in the alert list.
        $NewUserGraceDays = [int]($InputValue ?? 0)
        if ($Users -and $NewUserGraceDays -gt 0) {
            $CreatedByUpn = @{}
            try {
                foreach ($CachedUser in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users' -Fields 'userPrincipalName', 'createdDateTime')) {
                    if ($CachedUser.userPrincipalName) {
                        $CreatedByUpn[$CachedUser.userPrincipalName] = $CachedUser.createdDateTime
                    }
                }
            } catch {
                Write-Host "Could not load user createdDateTime from reporting DB for tenant '$TenantFilter': $_"
            }

            # No usable cache — same fields from live Graph, same filter rules below.
            if ($CreatedByUpn.Count -eq 0) {
                try {
                    foreach ($LiveUser in @(New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users?`$select=userPrincipalName,createdDateTime" -tenantid $TenantFilter)) {
                        if ($LiveUser.userPrincipalName) {
                            $CreatedByUpn[$LiveUser.userPrincipalName] = $LiveUser.createdDateTime
                        }
                    }
                } catch {
                    Write-Host "Could not load user createdDateTime from Graph for tenant '$TenantFilter': $_"
                }
            }

            if ($CreatedByUpn.Count -gt 0) {
                $Cutoff = (Get-Date).ToUniversalTime().AddDays(-$NewUserGraceDays)
                $Users = @($Users | Where-Object {
                        $Created = $CreatedByUpn[$_.UPN]
                        if (-not $Created) {
                            $true
                        } else {
                            try {
                                ([datetime]$Created).ToUniversalTime() -lt $Cutoff
                            } catch {
                                $true
                            }
                        }
                    })
            }
        }
        Write-Host "Completed MFA status check for tenant '$TenantFilter'. Found $($Users.Count) users without MFA registered."

        if ($Users) {
            $AlertData = foreach ($user in $Users) {
                [PSCustomObject]@{
                    UserPrincipalName = $user.UPN
                    DisplayName       = $user.DisplayName
                }
            }
            Write-Host 'Writing alert trace'
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        Write-LogMessage -message "Failed to check MFA status for all users: $($_.exception.message)" -API 'MFA Alerts - Informational' -tenant $TenantFilter -sev Error
    }

}
