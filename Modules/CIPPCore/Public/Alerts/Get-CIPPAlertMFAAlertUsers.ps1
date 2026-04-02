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
        Write-Host "Completed MFA status check for tenant '$TenantFilter'. Found $($Users.Count) users without MFA registered."

        if ($Users) {
            $AlertData = foreach ($user in $Users) {
                [PSCustomObject]@{
                    UserPrincipalName = $user.UPN
                    DisplayName       = $user.DisplayName
                }
            }
            Write-Host 'Writing alert trace'
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }

    } catch {
        Write-LogMessage -message "Failed to check MFA status for all users: $($_.exception.message)" -API 'MFA Alerts - Informational' -tenant $TenantFilter -sev Info
    }

}
