function Push-CIPPAlertMFAAlertUsers {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )
    try {

        $users = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?$filter=isMfaRegistered eq false' -tenantid $($QueueItem.tenant) 
        if ($users) {
            Write-AlertMessage -tenant $QueueItem.tenant -message "The following users do not have MFA registered: $($users.UserPrincipalName -join ', ')"
        }
        
    } catch {
        Write-LogMessage -message "Failed to check MFA status for all users: $($_.exception.message)" -API 'MFA Alerts - Informational' -tenant $QueueItem.tenant -sev Info
    }

}
