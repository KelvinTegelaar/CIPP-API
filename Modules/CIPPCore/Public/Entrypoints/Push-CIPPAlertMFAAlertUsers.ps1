function Push-CIPPAlertMFAAlertUsers {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $Item
    )
    try {

        $users = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?$filter=isMfaRegistered eq false and userType eq ''member''&$select=userPrincipalName,lastUpdatedDateTime,isMfaRegistered' -tenantid $($Item.tenant)
        if ($users.UserPrincipalName) {
            Write-AlertMessage -tenant $Item.tenant -message "The following $($users.Count) users do not have MFA registered: $($users.UserPrincipalName -join ', ')"
        }

    } catch {
        Write-LogMessage -message "Failed to check MFA status for all users: $($_.exception.message)" -API 'MFA Alerts - Informational' -tenant $Item.tenant -sev Info
    }

}
