function Push-CIPPAlertMFAAdmins {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )
    try {
        $CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?$top=999' -tenantid $QueueItem.tenant -ErrorAction Stop)
        foreach ($Policy in $CAPolicies) {
            if ($policy.grantControls.customAuthenticationFactors -eq 'RequireDuoMfa') {
                $DuoActive = $true
            }
        }
        if (!$DuoActive) {
            $users = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?$top=999&$filter=IsAdmin eq true' -tenantid $($QueueItem.tenant) | Where-Object -Property 'isMfaRegistered' -EQ $false
            if ($users) {
                Write-AlertMessage -tenant $QueueItem.tenant -message "The following admins do not have MFA registered: $($users.UserPrincipalName -join ', ')"
            }
        } else {
            Write-LogMessage -message 'Potentially using Duo for MFA, could not check MFA status for Admins with 100% accuracy' -API 'MFA Alerts - Informational' -tenant $QueueItem.tenant -sev Info
        }        
    } catch {
        Write-LogMessage -message "Failed to check MFA status for Admins: $($_.exception.message)" -API 'MFA Alerts - Informational' -tenant $QueueItem.tenant -sev Error
    }

}