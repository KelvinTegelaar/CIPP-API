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

        $Users = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?`$top=999&filter=IsAdmin eq false and isMfaRegistered eq false and userType eq 'member'&`$select=userDisplayName,userPrincipalName,lastUpdatedDateTime,isMfaRegistered,IsAdmin" -tenantid $($TenantFilter) -AsApp $true |
            Where-Object { $_.userDisplayName -ne 'On-Premises Directory Synchronization Service Account' -and $_.userPrincipalName -notmatch '^package_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@' }
        if ($Users) {
            $AlertData = foreach ($user in $Users) {
                [PSCustomObject]@{
                    UserPrincipalName = $user.userPrincipalName
                    DisplayName       = $user.userDisplayName
                    LastUpdated       = $user.lastUpdatedDateTime
                }
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

        }

    } catch {
        Write-LogMessage -message "Failed to check MFA status for all users: $($_.exception.message)" -API 'MFA Alerts - Informational' -tenant $TenantFilter -sev Info
    }

}
