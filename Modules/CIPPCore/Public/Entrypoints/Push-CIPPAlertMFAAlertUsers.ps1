function Push-CIPPAlertMFAAlertUsers {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )
    try {
        $users = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users?`$select=userPrincipalName,id,accountEnabled,userType&`$filter=userType eq 'Member' and accountEnabled eq true" -tenantid $($QueueItem.tenant)
        Write-Host "found $($users.count) users"
        $StrongMFAMethods = '#microsoft.graph.fido2AuthenticationMethod', '#microsoft.graph.phoneAuthenticationMethod', '#microsoft.graph.passwordlessmicrosoftauthenticatorauthenticationmethod', '#microsoft.graph.softwareOathAuthenticationMethod', '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'
        $users | ForEach-Object {
            try {
                $UPN = $_.UserPrincipalName
                        (New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$($_.ID)/authentication/Methods" -tenantid $($QueueItem.tenant)) | ForEach-Object {
                    $CARegistered = $false
                    if ($_.'@odata.type' -in $StrongMFAMethods) {
                        $CARegistered = $true
                    }
                    if ($CARegistered -eq $false) {
                        Write-AlertMessage -tenant $($QueueItem.tenant) -message "User $UPN is enabled but does not have any form of MFA configured."
                    }
                }
            } catch {
            }
        }
    } catch {
        Write-AlertMessage -tenant $($QueueItem.tenant) -message "Could not get MFA status for users for $($QueueItem.tenant): $(Get-NormalizedError -message $_.Exception.message)"
    }
}

