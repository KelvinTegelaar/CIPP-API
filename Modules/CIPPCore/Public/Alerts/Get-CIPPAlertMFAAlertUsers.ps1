function Get-CIPPAlertMFAAlertUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {

        $users = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?`$top=999&filter=IsAdmin eq false and isMfaRegistered eq false and userType eq 'member'&`$select=userDisplayName,userPrincipalName,lastUpdatedDateTime,isMfaRegistered,IsAdmin" -tenantid $($TenantFilter) -AsApp $true | Where-Object { $_.userDisplayName -ne 'On-Premises Directory Synchronization Service Account' }
        if ($users.UserPrincipalName) {
            $AlertData = "The following $($users.Count) users do not have MFA registered: $($users.UserPrincipalName -join ', ')"
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

        }

    } catch {
        Write-LogMessage -message "Failed to check MFA status for all users: $($_.exception.message)" -API 'MFA Alerts - Informational' -tenant $TenantFilter -sev Info
    }

}
